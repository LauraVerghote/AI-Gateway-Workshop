# Lab 4: Semantic Caching

> Cache similar prompts to reduce costs and improve latency

## Goal

In this lab you will:
- Configure **semantic caching** with an embedding model
- Test that similar questions return the same cached response
- Measure the **cost savings** and **latency improvement**
- Experiment with the `score-threshold` parameter

## Background

Semantic caching compares incoming prompts with previously seen prompts based on **meaning** (not exact match). Unlike traditional caching that requires an identical request, semantic caching uses an **embedding model** to convert prompts into vectors and compares them using cosine similarity. This can deliver **60-80% cost savings** for repetitive workloads.

```
Prompt 1: "What is the capital of the Netherlands?"     → Foundry call  → Store in cache
Prompt 2: "What's the capital of NL?"                   → Cache hit!    → No Foundry call (similar meaning)
Prompt 3: "Which city is the capital of Holland?"        → Cache hit!    → No Foundry call (similar meaning)
Prompt 4: "How many people live in Japan?"               → Foundry call  → Different topic, no cache hit
```

How it works internally:

1. **Incoming request** — APIM extracts the prompt and sends it to the embedding model to get a vector
2. **Cache lookup** — APIM compares the vector against previously cached vectors using cosine similarity
3. **Hit or miss** — If the similarity exceeds the `score-threshold`, the cached response is returned immediately without calling Foundry
4. **Cache store** — On a miss, the Foundry response is stored in the cache along with its vector for future lookups

## Prerequisites

- Completed Lab 3 (APIM instance with API configuration deployed)
- Microsoft Foundry with an **embedding model** (`text-embedding-3-small`) — already deployed by `main.bicep`
- **Azure Cache for Redis** — deployed automatically in this lab (required by APIM to store semantic cache vectors)

## Steps

### Step 1: Review the Semantic Cache Policy

Open `policies/semantic-cache.xml` and review the contents. This policy **replaces** the Lab 3 token rate limit policy with one that adds semantic caching:

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
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

Compared to the Lab 3 policy, the token rate limiting is removed and two new elements are added:

| Element | Section | What it does |
|---------|---------|-------------|
| `azure-openai-semantic-cache-lookup` | `inbound` | Converts the prompt to a vector via the embedding model, then checks the cache. If a similar prompt is found (similarity ≥ 0.8), returns the cached response immediately |
| `azure-openai-semantic-cache-store` | `outbound` | After a successful Foundry response, stores it in the cache with a 120-second TTL |

Key attributes explained:

| Attribute | Value | Purpose |
|-----------|-------|---------|
| `score-threshold` | `0.8` | How similar two prompts must be (0.0 = anything matches, 1.0 = exact match only). 0.8 is a good balance |
| `embeddings-backend-id` | `embeddings-backend` | The APIM backend pointing to the `text-embedding-3-small` model deployment |
| `embeddings-backend-auth` | `system-assigned` | Uses APIM's managed identity to authenticate to the embedding model (same identity as for chat) |
| `duration` | `120` | Cache entries expire after 120 seconds (2 minutes) |

> **Note:** The **order** in the inbound section matters. Authentication happens first, then cache lookup, then backend routing. If there's a cache hit, `set-backend-service` and the Foundry backend call are **skipped entirely** — saving both latency and tokens.

### Step 2: Deploy the Semantic Cache

This lab requires an **embeddings backend** in addition to the existing chat backend. The Bicep template (`infra/modules/apim-api.bicep`) supports this with the `enableEmbeddingsBackend` parameter, which creates an `embeddings-backend` in APIM pointing to the `text-embedding-3-small` model deployment on your Foundry instance.

Make sure you're in the `infra/` directory and your `$RESOURCE_GROUP` and `$LOCATION` variables are still set from Lab 1:

```powershell
# Read the semantic cache policy
$policyXml = Get-Content -Path "../policies/semantic-cache.xml" -Raw

@{
  '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
  contentVersion = '1.0.0.0'
  parameters = @{
    location                = @{ value = $LOCATION }
    enableApiConfig         = @{ value = $true }
    enableEmbeddingsBackend = @{ value = $true }
    policyXml               = @{ value = $policyXml }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-params.json" -Encoding utf8

# Deploy — this creates the embeddings backend and applies the semantic cache policy
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters temp-params.json
```

This deployment does three things on top of what Lab 3 deployed:
1. Creates an **Azure Cache for Redis** instance and configures it as APIM's external cache (required for storing semantic cache vectors)
2. Creates an **embeddings-backend** in APIM pointing to the `text-embedding-3-small` model
3. Replaces the token rate limit policy with the semantic cache policy

> ⏱️ Deployment takes **~5-10 minutes** on first run because Redis provisioning takes time. Subsequent deploys (e.g. policy changes) are faster since Redis already exists.

> **Why Redis?** APIM's semantic caching policies (`azure-openai-semantic-cache-lookup` / `azure-openai-semantic-cache-store`) require an external cache to store the embedding vectors and cached responses. Without Redis, the policies silently fall through and every request goes to Foundry.

### Step 3: Test Semantic Caching

Now let's verify that semantic caching works. We'll send three requests and compare latency:

1. An **original** question (cache miss — first time seeing this topic)
2. The **exact same** question (cache hit — proves caching works)
3. A **semantically similar** question (cache hit expected — same meaning, slightly different words)

```powershell
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

# Get the subscription key
$SUBSCRIPTION_ID = az account show --query "id" -o tsv
$SUB_KEY = (az rest --method post `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/test-sub/listSecrets?api-version=2024-05-01" `
  | ConvertFrom-Json).primaryKey

$headers = @{ 
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json" 
}

# Request 1: Original question (CACHE MISS)
Write-Host "`n--- Request 1: Original question ---" -ForegroundColor Cyan
$body1 = @{
    messages = @(@{ role = "user"; content = "What is the capital of the Netherlands?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response1 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body1
$sw.Stop()
$latency1 = $sw.ElapsedMilliseconds
$content1 = ($response1.Content | ConvertFrom-Json).choices[0].message.content
Write-Host "Latency: ${latency1}ms" -ForegroundColor Yellow
Write-Host "Response: $content1"

# Wait for the cache to store the entry
Start-Sleep -Seconds 5

# Request 2: Exact same question (CACHE HIT expected)
Write-Host "`n--- Request 2: Exact same question ---" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response2 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body1
$sw.Stop()
$latency2 = $sw.ElapsedMilliseconds
$content2 = ($response2.Content | ConvertFrom-Json).choices[0].message.content
Write-Host "Latency: ${latency2}ms" -ForegroundColor Yellow
Write-Host "Response: $content2"

# Request 3: Similar question, slightly different wording (CACHE HIT expected)
Write-Host "`n--- Request 3: Similar question (rephrased) ---" -ForegroundColor Cyan
$body3 = @{
    messages = @(@{ role = "user"; content = "What is the capital city of the Netherlands?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response3 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body3
$sw.Stop()
$latency3 = $sw.ElapsedMilliseconds
$content3 = ($response3.Content | ConvertFrom-Json).choices[0].message.content
Write-Host "Latency: ${latency3}ms" -ForegroundColor Yellow
Write-Host "Response: $content3"

# Summary
Write-Host "`n--- Summary ---" -ForegroundColor Green
Write-Host "Request 1 (original):  ${latency1}ms"
Write-Host "Request 2 (exact same): ${latency2}ms"
Write-Host "Request 3 (similar):   ${latency3}ms"

if ($content1 -eq $content2) {
    Write-Host "`nCache hit confirmed: Request 2 returned the exact same response as Request 1" -ForegroundColor Green
} else {
    Write-Host "`nCache miss: Request 2 returned a different response" -ForegroundColor Yellow
}
```

What to look for:

| Request | Expected | Why |
|---------|----------|-----|
| Request 1 | Cache **MISS**, ~500-2000ms | First time seeing this question — nothing in cache yet |
| Request 2 | Cache **HIT**, faster latency | Exact same prompt, should return **identical response** from cache |
| Request 3 | Cache **HIT** (possibly), similar latency to R2 | Very close wording — whether it hits depends on the similarity score exceeding the 0.8 threshold |

> **Tip:** The most reliable indicator of a cache hit is **identical response content**. A cached response returns the exact same text (LLM responses are normally non-deterministic). Latency improvement depends on network conditions, but cache hits are typically faster because they skip the Foundry call entirely.
>
> **Note:** With a `score-threshold` of 0.8, only very close rephrasings will match. Vastly different phrasings like "Tell me the capital of Holland" will likely miss. Lower the threshold to 0.7 for broader matching.

### Step 4: Experiment with parameters

To experiment, edit `policies/semantic-cache.xml`, change the values below, and re-run Step 2 to redeploy:

| Parameter | Value | Effect |
|-----------|-------|--------|
| `score-threshold` | `0.7` | More cache hits — even loosely related prompts match. Less accurate |
| `score-threshold` | **`0.8`** | **Balanced (recommended)** — phrases with the same meaning match |
| `score-threshold` | `0.9` | Fewer cache hits — only very similar phrasings match |
| `score-threshold` | `0.95` | Near exact match required — almost no caching benefit |
| `duration` | `60` | Cache entries expire after 1 minute (shorter TTL) |
| `duration` | `300` | Cache entries expire after 5 minutes (longer TTL, more savings) |

> **Tip:** After changing the XML, you need to redeploy (Step 2) for the changes to take effect. The policy is stored in APIM, not read from the file at runtime.

## Expected result

- ✅ Request 1: Cache miss, higher latency (~500-2000ms)
- ✅ Request 2: Cache hit, **identical response** to Request 1 (proves caching works)
- ✅ Request 3: Cache hit possible for close rephrasings (depends on similarity score)

## References

- [Semantic Caching Docs](https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching)
- [azure-openai-semantic-cache-lookup policy](https://learn.microsoft.com/azure/api-management/azure-openai-semantic-cache-lookup-policy)
- [Semantic Caching Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/semantic-caching)

---
**Previous lab:** [← Lab 3 - Token Rate Limiting](lab-03-token-rate-limiting.md)  
**Next lab:** [Lab 5 - Content Safety →](lab-05-content-safety.md)
