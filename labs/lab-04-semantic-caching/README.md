# Lab 4: Semantic Caching

> Cache similar prompts to reduce costs and improve latency

## Goal

In this lab you will:
- Configure **semantic caching** with an embedding model
- Test that similar questions return the same cached response
- Measure the **cost savings** and **latency improvement**
- Experiment with the `score-threshold` parameter

## Background

Semantic caching compares incoming prompts with previously seen prompts based on **meaning** (not exact match). This can deliver **60-80% cost savings**.

```
Prompt 1: "What is the capital of the Netherlands?"     → Foundry call  → Store in cache
Prompt 2: "What's the capital of NL?"                   → Cache hit!    → No Foundry call
Prompt 3: "Which city is the capital of Holland?"        → Cache hit!    → No Foundry call
```

## Prerequisites

- Microsoft Foundry with an **embedding model** (text-embedding-3-small)
- This is already deployed if you used `main.bicep`

## Steps

### Step 1: Create an Embedding Backend in APIM

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$AIS_NAME = az cognitiveservices account list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$AIS_ENDPOINT = az cognitiveservices account show -n $AIS_NAME -g $RESOURCE_GROUP --query "properties.endpoint" -o tsv

# Backend for embeddings
az apim backend create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --backend-id "embeddings-backend" `
  --protocol "http" `
  --url "${AIS_ENDPOINT}openai/deployments/text-embedding-3-small"
```

### Step 2: Apply the Semantic Cache Policy

```xml
<!-- policies/semantic-cache.xml -->
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

        <!-- Semantic cache lookup -->
        <azure-openai-semantic-cache-lookup 
            score-threshold="0.8" 
            embeddings-backend-id="embeddings-backend" 
            embeddings-backend-auth="system-assigned" />

        <set-backend-service backend-id="openai-backend" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <!-- Store response in cache (120 seconds) -->
        <azure-openai-semantic-cache-store duration="120" />

        <!-- Add cache status header -->
        <set-header name="X-Cache-Status" exists-action="override">
            <value>@(context.Response.Headers.ContainsKey("x-]]ms-apim-cache-hit") ? "HIT" : "MISS")</value>
        </set-header>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Step 3: Apply the policy

```powershell
az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/semantic-cache.xml"
```

### Step 4: Test semantic caching

```powershell
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

$headers = @{ 
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json" 
}

# Request 1: Original question (CACHE MISS)
Write-Host "`n--- Request 1: Original ---" -ForegroundColor Cyan
$body1 = @{
    messages = @(@{ role = "user"; content = "What is the capital of the Netherlands?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response1 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body1
$sw.Stop()
Write-Host "Latency: $($sw.ElapsedMilliseconds)ms"
Write-Host "Cache: $($response1.Headers['X-Cache-Status'])"

Start-Sleep -Seconds 2

# Request 2: Similar question (CACHE HIT expected)
Write-Host "`n--- Request 2: Similar ---" -ForegroundColor Cyan
$body2 = @{
    messages = @(@{ role = "user"; content = "What's the capital of NL?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response2 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body2
$sw.Stop()
Write-Host "Latency: $($sw.ElapsedMilliseconds)ms"
Write-Host "Cache: $($response2.Headers['X-Cache-Status'])"

# Request 3: Completely different question (CACHE MISS expected)
Write-Host "`n--- Request 3: Different question ---" -ForegroundColor Cyan
$body3 = @{
    messages = @(@{ role = "user"; content = "How many inhabitants does Japan have?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response3 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body3
$sw.Stop()
Write-Host "Latency: $($sw.ElapsedMilliseconds)ms"
Write-Host "Cache: $($response3.Headers['X-Cache-Status'])"
```

### Step 5: Experiment with score-threshold

| Score Threshold | Behavior |
|----------------|----------|
| 0.7 | Many cache hits, less accurate |
| **0.8** | **Balanced (recommended)** |
| 0.9 | Few cache hits, very accurate |
| 0.95 | Near exact match required |

## Expected result

- ✅ Request 1: Cache MISS, higher latency (~500-2000ms)
- ✅ Request 2: Cache HIT, lower latency (~50-200ms), same response
- ✅ Request 3: Cache MISS, new question is not cached

## References

- [Semantic Caching Docs](https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching)
- [Semantic Caching Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/semantic-caching)

---
**Previous lab:** [← Lab 3 - Token Rate Limiting](../lab-03-token-rate-limiting/README.md)  
**Next lab:** [Lab 5 - Content Safety →](../lab-05-content-safety/README.md)
