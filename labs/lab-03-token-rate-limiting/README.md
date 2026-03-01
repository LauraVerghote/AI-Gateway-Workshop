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

### Step 1: Apply the Token Rate Limit Policy

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
            <value>@(context.Variables.GetValueOrDefault<int>("remainingTokens", 0).ToString())</value>
        </set-header>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Step 2: Apply the policy

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/token-rate-limit.xml"
```

### Step 3: Test the rate limiting

```powershell
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

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
            Write-Host "Rate limit reached! ✅ Working correctly." -ForegroundColor Yellow
        }
    }
}
```

### Step 4: Experiment with parameters

Adjust the policy and test:

| Parameter | Value | Effect |
|-----------|-------|--------|
| `tokens-per-minute` | 100 | Very restrictive - quick 429 |
| `tokens-per-minute` | 5000 | Normal usage |
| `tokens-per-minute` | 50000 | High volume |
| `estimate-prompt-tokens` | true | Faster but less accurate |
| `counter-key` | `Request.IpAddress` | Limit per IP instead of subscription |

## Expected result

- ✅ First requests succeed (HTTP 200) with `X-Tokens-Remaining` header
- ✅ After exceeding the limit you get HTTP 429 (Too Many Requests)
- ✅ After 1 minute the counter resets and you can make requests again

## References

- [Azure OpenAI Token Limit Policy](https://learn.microsoft.com/azure/api-management/azure-openai-token-limit-policy)
- [Token Rate Limiting Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/token-rate-limiting)

---
**Previous lab:** [← Lab 2 - OpenAI Backend](../lab-02-add-openai-backend/README.md)  
**Next lab:** [Lab 4 - Semantic Caching →](../lab-04-semantic-caching/README.md)
