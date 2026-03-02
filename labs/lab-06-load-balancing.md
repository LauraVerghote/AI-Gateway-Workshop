# Lab 6: Load Balancing with Retry

> Distribute traffic across multiple Microsoft Foundry backends with automatic failover

## Goal

In this lab you will:
- Deploy a **second Microsoft Foundry** instance in a different region (East US)
- Configure a **backend pool** in APIM that distributes traffic across both instances
- Set up **automatic retry** on 429 (rate limit) or 503 (unavailable) errors
- Test that requests are load balanced and failover works

## Background

### Why load balance?

A single Foundry instance has **quota limits** — a maximum number of tokens per minute (TPM) for each model deployment. When your application exceeds this limit, the API returns `429 Too Many Requests`. Load balancing solves this and more:

| Problem | How load balancing helps |
|---------|--------------------------|
| **Quota limits** | Spread requests across multiple instances to get 2x (or more) the TPM |
| **Regional outages** | If one region goes down, traffic automatically routes to the other |
| **Latency** | Users in different regions get routed to a closer backend |
| **Cost distribution** | Spread consumption across multiple subscriptions or billing accounts |

### How it works in APIM

APIM uses a **backend pool** — a single logical backend that contains multiple individual backends. When the policy says `set-backend-service backend-id="openai-pool"`, APIM picks one of the backends based on **priority** and **weight**:

```
                    ┌── Microsoft Foundry (Sweden Central)  [weight: 60]
Client → APIM ─────>│                                        priority: 1
                    └── Microsoft Foundry (East US)         [weight: 40]
                                                             priority: 1
```

- **Priority** — lower numbers are tried first. Backends with the same priority share traffic.
- **Weight** — within the same priority, traffic is distributed proportionally. 60/40 means ~60% of requests go to Sweden Central and ~40% to East US.

If a backend returns `429` or `503`, the **retry policy** in the `<backend>` section automatically tries another backend from the pool — all transparent to the client.

## Understanding the Bicep

This lab adds several new resources to the infrastructure. Here's what `enableSecondaryFoundry=true` triggers:

### 1. Secondary Foundry Instance

A second `Microsoft.CognitiveServices/accounts` resource is deployed in East US (configured in `main.bicepparam`). It gets the same model deployments (gpt-4o-mini + text-embedding-3-small) as the primary instance, giving you double the quota.

### 2. RBAC for the Secondary Instance

APIM's managed identity needs `Cognitive Services OpenAI User` access on the secondary Foundry instance too — without this, the managed identity token from the policy won't be accepted.

### 3. Secondary Backend + Backend Pool

In `apim-api.bicep`, two new resources are created when a secondary endpoint is provided:

- **`openai-backend-secondary`** — points to the secondary Foundry's `/openai` endpoint
- **`openai-pool`** — a pool-type backend containing both the primary (`openai-backend`, weight 60) and secondary (`openai-backend-secondary`, weight 40) backends

The policy then references `openai-pool` instead of `openai-backend`, and APIM handles the distribution automatically.

### 4. Retry in the Backend Section

The load balancing policy moves the `<forward-request>` into a `<retry>` block:

```xml
<backend>
    <retry count="2" interval="0" first-fast-retry="true"
        condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode == 503)">
        <set-backend-service backend-id="openai-pool" />
        <forward-request buffer-request-body="true" />
    </retry>
</backend>
```

This means: if the selected backend returns 429 or 503, immediately pick another backend from the pool and retry (up to 2 times). `buffer-request-body="true"` is essential — without it, the request body can't be re-sent on retry.

## Steps

### Step 1: Review the load balancing policy

Open `policies/load-balancing.xml` and review how it differs from the managed identity policy in Lab 2:

```xml
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
        <!-- Use backend pool for load balancing -->
        <set-backend-service backend-id="openai-pool" />
    </inbound>
    <backend>
        <!-- Retry on 429 (rate limit) or 503 (service unavailable) -->
        <retry count="2" interval="0" first-fast-retry="true" 
            condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode == 503)">
            <set-backend-service backend-id="openai-pool" />
            <forward-request buffer-request-body="true" />
        </retry>
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

Two key differences from Lab 2's policy:

| Section | Lab 2 (basic) | Lab 6 (load balanced) |
|---------|---------------|------------------------|
| `inbound` | `set-backend-service backend-id="openai-backend"` | `set-backend-service backend-id="openai-pool"` |
| `backend` | `<base />` (default forward) | `<retry>` block with failover logic |

The `inbound` section is identical except for the backend ID — the authentication and managed identity token handling stays the same. The real change is in the `backend` section where the default forwarding behavior is replaced with retry logic.

### Step 2: Deploy the secondary Foundry and backend pool

> **If you opened a new terminal since Lab 1**, set your variables again:
> ```powershell
> $RESOURCE_GROUP = "rg-aigateway-workshop"
> $LOCATION = "swedencentral"
> ```

Make sure you're in the `infra/` directory, then deploy:

```powershell
# Read the load balancing policy
$policyXml = Get-Content -Path "../policies/load-balancing.xml" -Raw

@{
  '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
  contentVersion = '1.0.0.0'
  parameters = @{
    location              = @{ value = $LOCATION }
    enableApiConfig       = @{ value = $true }
    enableSecondaryFoundry = @{ value = $true }
    policyXml             = @{ value = $policyXml }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-params.json" -Encoding utf8

# Deploy secondary Foundry + backend pool
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters temp-params.json
```

This deployment does the following:

| Resource | Type | What it does |
|----------|------|-------------|
| `ais-aigateway2-<suffix>` | Microsoft Foundry (East US) | Second AI Services instance with gpt-4o-mini + embeddings |
| RBAC assignment | Role Assignment | Gives APIM managed identity access to the secondary Foundry |
| `openai-backend-secondary` | APIM Backend | Points to the secondary Foundry endpoint |
| `openai-pool` | APIM Backend Pool | Distributes traffic 60/40 across primary and secondary |
| Updated policy | APIM API Policy | Switches from single backend to pool + retry |

> ⏱️ **Note**: This deployment takes longer than previous labs (~8-12 minutes) because it provisions a new Foundry instance and waits for model deployments. The RBAC assignment also needs time to propagate.

### Step 3: Retrieve the gateway URL and subscription key

```powershell
# Get APIM name
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# Get the gateway URL
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

# Get your subscription ID
$SUBSCRIPTION_ID = az account show --query "id" -o tsv

# Get the test subscription key
$SUB_KEY = (az rest --method post `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/test-sub/listSecrets?api-version=2024-05-01" `
  | ConvertFrom-Json).primaryKey

Write-Host "Gateway URL: $GATEWAY_URL"
Write-Host "Subscription Key: $SUB_KEY"
```

### Step 4: Verify the backend pool was created

Before testing, confirm the pool and its backends exist in APIM:

```powershell
# List all backends — you should see openai-backend, openai-backend-secondary, and openai-pool
az rest --method get `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/backends?api-version=2024-06-01-preview" `
  | ConvertFrom-Json | Select-Object -ExpandProperty value | Select-Object name, @{N='type';E={$_.properties.type}}, @{N='url';E={$_.properties.url}} | Format-Table
```

You should see three backends:

| Name | Type | URL |
|------|------|-----|
| `openai-backend` | *(single)* | `https://ais-aigateway-xxx.openai.azure.com/openai` |
| `openai-backend-secondary` | *(single)* | `https://ais-aigateway2-xxx.openai.azure.com/openai` |
| `openai-pool` | Pool | *(empty — pool uses its member backends)* |

### Step 5: Test load balancing

Send multiple requests through the gateway. The backend pool distributes them across both Foundry instances:

```powershell
$headers = @{
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json"
}

# Send 5 requests and verify they all succeed
for ($i = 1; $i -le 5; $i++) {
    $body = @{
        messages = @(@{ role = "user"; content = "Say 'Hello from request $i' and nothing else." })
        model = "gpt-4o-mini"
        max_tokens = 20
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod `
          -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
          -Method POST -Headers $headers -Body $body

        Write-Host "Request $i - OK: $($response.choices[0].message.content)" -ForegroundColor Green
    } catch {
        Write-Host "Request $i - Error: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}
```

All requests should succeed. The backend pool distributes them across your two Foundry instances automatically — you won't see which backend handled which request at this level (the pool is invisible to the client). In Lab 7, you'll use Application Insights to see the actual backend distribution.

> **Tip:** To test the retry/failover behavior, you could temporarily lower the TPM quota on one of your Foundry deployments to trigger 429 errors. The retry policy will automatically route those requests to the other backend.

## Expected result

After this lab you will have:
- ✅ Two Microsoft Foundry instances (Sweden Central + East US)
- ✅ APIM backend pool distributing traffic 60/40
- ✅ Automatic retry on 429 (rate limit) and 503 (unavailable)
- ✅ All requests succeeding through the load balanced gateway

## Architecture

```
                                      ┌──────────────────────────┐
                                 60%  │  Microsoft Foundry       │
                              ┌──────►│  (Sweden Central)        │
Client                        │       │  - gpt-4o-mini           │
  │                           │       └──────────────────────────┘
  ▼                           │
┌───────────────────┐         │
│  API Management   │─────────┤ Backend Pool
│  (Gateway)        │  retry  │ "openai-pool"
│  - Auth: MI       │◄────────┤
│  - Retry: 429/503 │         │       ┌──────────────────────────┐
└───────────────────┘         │  40%  │  Microsoft Foundry       │
                              └──────►│  (East US)               │
                                      │  - gpt-4o-mini           │
                                      └──────────────────────────┘
```

## References

- [Backend Pool Load Balancing](https://learn.microsoft.com/azure/api-management/backends?tabs=bicep)
- [Load Balancing Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/backend-pool-load-balancing)
- [Retry Policy](https://learn.microsoft.com/azure/api-management/retry-policy)

---
**Previous lab:** [← Lab 5 - Content Safety](lab-05-content-safety.md)  
**Next lab:** [Lab 7 - Monitoring →](lab-07-monitoring.md)
