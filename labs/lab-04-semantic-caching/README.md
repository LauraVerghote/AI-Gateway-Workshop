# Lab 4: Semantic Caching

> Cache vergelijkbare prompts om kosten te verlagen en latency te verbeteren

## Doel

In deze lab:
- Configureer je **semantic caching** met een embedding model
- Test je dat vergelijkbare vragen dezelfde cached response opleveren
- Meet je de **kostenbesparing** en **latency verbetering**
- Experimenteer je met de `score-threshold` parameter

## Achtergrond

Semantic caching vergelijkt binnenkomende prompts met eerder geziene prompts op basis van **betekenis** (niet exact match). Dit kan **60-80% kostenbesparing** opleveren.

```
Prompt 1: "Wat is de hoofdstad van Nederland?"     → OpenAI call → Cache opslaan
Prompt 2: "Wat is de hoofdstad van NL?"             → Cache hit!  → Geen OpenAI call
Prompt 3: "Welke stad is de hoofdstad van Holland?"  → Cache hit!  → Geen OpenAI call
```

## Vereisten

- Azure OpenAI met een **embedding model** (text-embedding-3-small)
- Dit is al gedeployed als je `main.bicep` hebt gebruikt

## Stappen

### Stap 1: Maak een Embedding Backend in APIM

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$OAI_NAME = az cognitiveservices account list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$OAI_ENDPOINT = az cognitiveservices account show -n $OAI_NAME -g $RESOURCE_GROUP --query "properties.endpoint" -o tsv

# Backend voor embeddings
az apim backend create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --backend-id "embeddings-backend" `
  --protocol "http" `
  --url "${OAI_ENDPOINT}openai/deployments/text-embedding-3-small"
```

### Stap 2: Pas de Semantic Cache Policy toe

```xml
<!-- policies/semantic-cache.xml -->
<policies>
    <inbound>
        <base />
        <!-- Authenticeer met managed identity -->
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
        <!-- Sla response op in cache (120 seconden) -->
        <azure-openai-semantic-cache-store duration="120" />

        <!-- Voeg cache status header toe -->
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

### Stap 3: Apply de policy

```powershell
az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/semantic-cache.xml"
```

### Stap 4: Test semantic caching

```powershell
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

$headers = @{ 
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json" 
}

# Request 1: Originele vraag (CACHE MISS)
Write-Host "`n--- Request 1: Origineel ---" -ForegroundColor Cyan
$body1 = @{
    messages = @(@{ role = "user"; content = "Wat is de hoofdstad van Nederland?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response1 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body1
$sw.Stop()
Write-Host "Latency: $($sw.ElapsedMilliseconds)ms"
Write-Host "Cache: $($response1.Headers['X-Cache-Status'])"

Start-Sleep -Seconds 2

# Request 2: Vergelijkbare vraag (CACHE HIT verwacht)
Write-Host "`n--- Request 2: Vergelijkbaar ---" -ForegroundColor Cyan
$body2 = @{
    messages = @(@{ role = "user"; content = "Wat is de hoofdstad van NL?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response2 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body2
$sw.Stop()
Write-Host "Latency: $($sw.ElapsedMilliseconds)ms"
Write-Host "Cache: $($response2.Headers['X-Cache-Status'])"

# Request 3: Geheel andere vraag (CACHE MISS verwacht)
Write-Host "`n--- Request 3: Andere vraag ---" -ForegroundColor Cyan
$body3 = @{
    messages = @(@{ role = "user"; content = "Hoeveel inwoners heeft Japan?" })
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$response3 = Invoke-WebRequest -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" -Method POST -Headers $headers -Body $body3
$sw.Stop()
Write-Host "Latency: $($sw.ElapsedMilliseconds)ms"
Write-Host "Cache: $($response3.Headers['X-Cache-Status'])"
```

### Stap 5: Experimenteer met score-threshold

| Score Threshold | Gedrag |
|----------------|--------|
| 0.7 | Veel cache hits, minder nauwkeurig |
| **0.8** | **Balans (aanbevolen)** |
| 0.9 | Weinig cache hits, zeer nauwkeurig |
| 0.95 | Bijna exact match nodig |

## Verwacht resultaat

- ✅ Request 1: Cache MISS, hogere latency (~500-2000ms)
- ✅ Request 2: Cache HIT, lagere latency (~50-200ms), zelfde response
- ✅ Request 3: Cache MISS, nieuwe vraag wordt niet gecached

## Referenties

- [Semantic Caching Docs](https://learn.microsoft.com/azure/api-management/azure-openai-enable-semantic-caching)
- [Semantic Caching Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/semantic-caching)

---
**Vorige lab:** [← Lab 3 - Token Rate Limiting](../lab-03-token-rate-limiting/README.md)  
**Volgende lab:** [Lab 5 - Content Safety →](../lab-05-content-safety/README.md)
