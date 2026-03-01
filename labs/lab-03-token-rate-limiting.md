# Lab 3: Token Rate Limiting

> Limit token consumption per minute to control costs and prevent abuse

## Goal

In this lab you will:
- Configure **token rate limiting** per subscription
- Test that requests are blocked when the limit is exceeded (HTTP 429)
- Learn to read the `remainingTokens` response header
- Experiment with different limits

## Background

Token rate limiting is crucial for AI Gateway scenarios:

| Problem | Solution |
|---------|----------|
| One user consumes all your quota | Limit per subscription/IP |
| Unexpectedly high costs | Hard token maximum per minute |
| DDoS/abuse | Automatic blocking when limit is exceeded |

## Steps

### Step 1: Review the Token Rate Limit Policy

In Lab 2, we deployed a basic managed identity authentication policy. Now we're going to **replace** that policy with one that adds token rate limiting on top of the same authentication.

Open `policies/token-rate-limit.xml` and review the contents. This is the policy we'll apply to the API:

```xml
<!-- policies/token-rate-limit.xml -->
<policies>
    <inbound>
        <base />
        <!-- Authenticate with managed identity -->
        <authentication-managed-identity 
            resource="https://cognitiveservices.azure.com" 
            output-token-variable-name="managed-id-access-token" 
            ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
        </set-header>
        <set-backend-service backend-id="openai-backend" />
        
        <!-- Token rate limiting: max 500 tokens per minute per subscription -->
        <azure-openai-token-limit 
            counter-key="@(context.Subscription.Id)"
            tokens-per-minute="500" 
            estimate-prompt-tokens="false" 
            remaining-tokens-variable-name="remainingTokens" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <!-- Show remaining tokens in response header -->
        <set-header name="X-Tokens-Remaining" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault&lt;int&gt;("remainingTokens", 0).ToString())</value>
        </set-header>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

Compared to the Lab 2 policy, this adds two new elements:

| Element | Section | What it does |
|---------|---------|-------------|
| `azure-openai-token-limit` | `inbound` | Counts tokens per subscription and blocks requests when the limit (500 tokens/min) is exceeded with HTTP 429 |
| `set-header X-Tokens-Remaining` | `outbound` | Adds a response header showing how many tokens the caller has left this minute |

The `counter-key` is set to `context.Subscription.Id`, meaning each APIM subscription gets its own independent token budget. You could also use `context.Request.IpAddress` to limit per IP address.

### Step 2: Deploy the updated policy

We'll redeploy the Bicep template with the new policy XML, just like in Lab 2. The deployment replaces the existing policy on the API with the new token-rate-limit version.

Make sure you're in the `infra/` directory and your `$RESOURCE_GROUP` and `$LOCATION` variables are still set from Lab 1:

```powershell
# Read the new policy XML and create a parameters file
$policyXml = Get-Content -Path "../policies/token-rate-limit.xml" -Raw

@{
  '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
  contentVersion = '1.0.0.0'
  parameters = @{
    location       = @{ value = $LOCATION }
    enableApiConfig = @{ value = $true }
    policyXml      = @{ value = $policyXml }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-params.json" -Encoding utf8

# Deploy the updated policy
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters temp-params.json
```

> ⏱️ This reuses the same APIM instance and API from Lab 2 — only the policy content changes. Deployment takes ~1-2 minutes.

> **Important:** The Bicep template (`infra/modules/apim-api.bicep`) uses `format: 'rawxml'` when applying the policy. This is required because the policy XML contains C#-style expressions like `GetValueOrDefault<int>(...)`, which must be escaped as `&lt;int&gt;` in XML. If you use `format: 'xml'` instead, ARM will double-decode the entities and the deployment will fail with: *"The 'int' start tag does not match the end tag of 'value'"*.

### Step 3: Test the rate limiting

Now let's verify the rate limit works. We'll send 5 requests in a row, each asking for up to 200 tokens. With a limit of 500 tokens per minute, we should hit the limit after 2-3 responses:

```powershell
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

# Get the subscription key
$SUBSCRIPTION_ID = az account show --query "id" -o tsv
$SUB_KEY = (az rest --method post `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/test-sub/listSecrets?api-version=2024-05-01" `
  | ConvertFrom-Json).primaryKey

# Send multiple requests to reach the limit
for ($i = 1; $i -le 5; $i++) {
    Write-Host "`n--- Request $i ---" -ForegroundColor Cyan
    
    $body = @{
        messages = @(@{ role = "user"; content = "Write a long story about Azure." })
        model = "gpt-4o-mini"
        max_tokens = 200
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-WebRequest `
            -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
            -Method POST `
            -Headers @{ 
                "Ocp-Apim-Subscription-Key" = $SUB_KEY
                "Content-Type" = "application/json" 
            } `
            -Body $body

        Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "Tokens remaining: $($response.Headers['X-Tokens-Remaining'])"
    }
    catch {
        Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        if ($_.Exception.Response.StatusCode.value__ -eq 429) {
            Write-Host "Rate limit reached! Working correctly." -ForegroundColor Yellow
        }
    }
}
```

What to look for:
- The first few requests should succeed (HTTP 200) with a decreasing `Tokens remaining` value
- Once the budget is exhausted, subsequent requests return **HTTP 429 (Too Many Requests)**
- After waiting 1 minute, the counter resets and requests succeed again

### Step 4: Experiment with parameters

To experiment, edit `policies/token-rate-limit.xml`, change the values below, and re-run Step 2 to redeploy:

| Parameter | Value | Effect |
|-----------|-------|--------|
| `tokens-per-minute` | 100 | Very restrictive — you'll hit 429 after 1 request |
| `tokens-per-minute` | 5000 | Normal usage — allows several conversations per minute |
| `tokens-per-minute` | 50000 | High volume — unlikely to hit the limit |
| `estimate-prompt-tokens` | true | Estimates prompt tokens before sending to the backend (faster, but less accurate) |
| `counter-key` | `@(context.Request.IpAddress)` | Limit per IP address instead of per subscription |

> **Tip:** After changing the XML, you need to redeploy (Step 2) for the changes to take effect. The policy is stored in APIM, not read from the file at runtime.

## Expected result

- ✅ First requests succeed (HTTP 200) with `X-Tokens-Remaining` header
- ✅ After exceeding the limit you get HTTP 429 (Too Many Requests)
- ✅ After 1 minute the counter resets and you can make requests again

## References

- [Azure OpenAI Token Limit Policy](https://learn.microsoft.com/azure/api-management/azure-openai-token-limit-policy)
- [Token Rate Limiting Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/token-rate-limiting)

---
**Previous lab:** [← Lab 2 - Foundry Backend](lab-02-add-openai-backend.md)  
**Next lab:** [Lab 4 - Semantic Caching →](lab-04-semantic-caching.md)
