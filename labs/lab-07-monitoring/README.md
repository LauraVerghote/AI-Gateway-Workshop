# Lab 7: Monitoring & Token Metrics

> Stel monitoring in met Application Insights en volg token-verbruik per subscription

## Doel

In deze lab:
- Configureer je **token metrics** met `azure-openai-emit-token-metric`
- Bekijk je token-verbruik in **Application Insights**
- Stel je **LLM request logging** in
- Bouw je een **KQL query** voor een token usage dashboard

## Achtergrond

Monitoring is cruciaal voor productie AI Gateways:

| Metric | Beschrijving |
|--------|-------------|
| Prompt tokens | Tokens in de input |
| Completion tokens | Tokens in de output |
| Total tokens | Totaal verbruik |
| Tokens per subscription | Verbruik per klant/team |
| Cache hit ratio | Effectiviteit van semantic caching |

## Stappen

### Stap 1: Pas de Monitoring Policy toe

Deze policy combineert **alle voorgaande labs** met monitoring:

```xml
<!-- Finale productie-policy: combinatie van alle labs -->
<policies>
    <inbound>
        <base />
        
        <!-- 1. Managed Identity authenticatie -->
        <authentication-managed-identity 
            resource="https://cognitiveservices.azure.com" 
            output-token-variable-name="managed-id-access-token" 
            ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
        </set-header>

        <!-- 2. Token rate limiting -->
        <azure-openai-token-limit 
            counter-key="@(context.Subscription.Id)"
            tokens-per-minute="5000" 
            estimate-prompt-tokens="false" 
            remaining-tokens-variable-name="remainingTokens" />

        <!-- 3. Semantic caching -->
        <azure-openai-semantic-cache-lookup 
            score-threshold="0.8" 
            embeddings-backend-id="embeddings-backend" 
            embeddings-backend-auth="system-assigned" />

        <!-- 4. Backend routing -->
        <set-backend-service backend-id="openai-backend" />

        <!-- 5. Token metrics emitting -->
        <azure-openai-emit-token-metric namespace="AIGateway">
            <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
            <dimension name="Client IP" value="@(context.Request.IpAddress)" />
            <dimension name="API ID" value="@(context.Api.Id)" />
            <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
        </azure-openai-emit-token-metric>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <!-- Cache store -->
        <azure-openai-semantic-cache-store duration="120" />
        
        <!-- Response headers voor debugging -->
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

### Stap 2: Schakel LLM Request Logging in

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# Diagnostic settings voor de API
az apim api diagnostic create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --diagnostic-id "applicationinsights" `
  --logger-id "app-insights-logger" `
  --sampling-percentage 100 `
  --always-log "allErrors"
```

### Stap 3: Genereer test-verkeer

```powershell
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

$headers = @{ 
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json" 
}

$vragen = @(
    "Wat is Azure API Management?",
    "Leg uit hoe semantic caching werkt.",
    "Wat zijn de voordelen van load balancing?",
    "Hoe werkt token rate limiting?",
    "Wat is een managed identity?",
    "Beschrijf de AI Gateway architectuur.",
    "Wat is Azure API Management?",   # Duplicate voor cache test
    "Hoe werkt semantic caching?"      # Similar voor cache test
)

foreach ($vraag in $vragen) {
    Write-Host "Vraag: $vraag" -ForegroundColor Cyan
    $body = @{
        messages = @(@{ role = "user"; content = $vraag })
        model = "gpt-4o-mini"
        max_tokens = 100
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-WebRequest `
            -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
            -Method POST -Headers $headers -Body $body
        Write-Host "  Tokens remaining: $($response.Headers['X-Tokens-Remaining'])" -ForegroundColor Green
    } catch {
        Write-Host "  Error: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 1
}
```

### Stap 4: Bekijk metrics in Application Insights

Open de Azure Portal en navigeer naar Application Insights:

1. **Application Insights** → **Metrics**
2. Metric namespace: **AIGateway** (custom namespace)
3. Beschikbare metrics:
   - `Prompt Token Count`
   - `Completion Token Count`
   - `Total Token Count`
4. Split by: `Subscription ID`, `Model`, `API ID`

### Stap 5: KQL Queries voor dashboards

Open **Application Insights → Logs** en voer deze queries uit:

#### Token verbruik per uur

```kql
customMetrics
| where name startswith "AIGateway"
| summarize TotalTokens = sum(value) by bin(timestamp, 1h), tostring(customDimensions["Subscription ID"])
| render timechart
```

#### Top 10 subscription per token-verbruik

```kql
customMetrics
| where name == "AIGateway/Total Token Count"
| summarize TotalTokens = sum(value) by tostring(customDimensions["Subscription ID"])
| top 10 by TotalTokens desc
| render barchart
```

#### Cache hit ratio

```kql
requests
| where url contains "chat/completions"
| extend CacheHit = iff(duration < 200, "Hit", "Miss")
| summarize Count = count() by CacheHit
| render piechart
```

#### Errors en rate limits

```kql
requests
| where resultCode == "429" or resultCode startswith "5"
| summarize ErrorCount = count() by bin(timestamp, 5m), resultCode
| render timechart
```

## Verwacht resultaat

- ✅ Token metrics zichtbaar in Application Insights
- ✅ Custom dimensions (Subscription ID, Model) beschikbaar voor filtering
- ✅ KQL queries tonen token-verbruik patronen
- ✅ Cache hits vs misses zijn meetbaar

## Architectuur (Compleet)

```
                                    ┌─────────────────────┐
                                    │  Application        │
                                    │  Insights           │
                                    │  - Token metrics    │
                                    │  - Request logs     │
                                    │  - KQL dashboards   │
                                    └──────▲──────────────┘
                                           │ Telemetry
┌──────────┐    ┌──────────────────────────┴───────────────────┐
│  Client   │──►│  API Management (AI Gateway)                 │
│  Apps     │   │                                              │
│           │◄──│  Policies:                                   │
└──────────┘    │  1. ✅ Managed Identity Auth                 │
                │  2. ✅ Token Rate Limiting (500 TPM)         │
                │  3. ✅ Semantic Caching (0.8 threshold)      │
                │  4. ✅ Content Safety                        │
                │  5. ✅ Token Metrics Emission                │
                │  6. ✅ Load Balancing + Retry                │
                └──────┬───────────────────┬───────────────────┘
                       │                   │
              ┌────────▼────────┐ ┌────────▼────────┐
              │ Azure OpenAI    │ │ Azure OpenAI    │
              │ Sweden Central  │ │ West Europe     │
              │ - gpt-4o-mini   │ │ - gpt-4o-mini   │
              │ - embeddings    │ │ - embeddings    │
              └─────────────────┘ └─────────────────┘
```

## Referenties

- [Token Metrics Policy](https://learn.microsoft.com/azure/api-management/azure-openai-emit-token-metric-policy)
- [LLM Logs & Token Limits](https://learn.microsoft.com/azure/api-management/api-management-howto-llm-logs)
- [Monitoring Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/zero-to-production)

---
**Vorige lab:** [← Lab 6 - Load Balancing](../lab-06-load-balancing/README.md)

---

## 🎉 Gefeliciteerd!

Je hebt de volledige AI Gateway Workshop afgerond! Je hebt nu een productie-klare AI Gateway met:

- ✅ API Management als centraal toegangspunt
- ✅ Managed identity authenticatie (geen API keys)
- ✅ Token rate limiting voor kostenbeheer
- ✅ Semantic caching voor kostenbesparing
- ✅ Content safety voor veilige AI
- ✅ Load balancing voor hoge beschikbaarheid
- ✅ Monitoring met Application Insights
