# Lab 7: Monitoring & Token Metrics

> Set up monitoring with Application Insights and track token consumption per subscription

## Goal

In this lab you will:
- Configure **token metrics** with `azure-openai-emit-token-metric`
- View token consumption in **Application Insights**
- Set up **LLM request logging**
- Build a **KQL query** for a token usage dashboard

## Background

Monitoring is crucial for production AI Gateways:

| Metric | Description |
|--------|-------------|
| Prompt tokens | Tokens in the input |
| Completion tokens | Tokens in the output |
| Total tokens | Total consumption |
| Tokens per subscription | Consumption per customer/team |
| Cache hit ratio | Effectiveness of semantic caching |

## Steps

### Step 1: Apply the Monitoring Policy

This policy combines **all previous labs** with monitoring:

```xml
<!-- Final production policy: combination of all labs -->
<policies>
    <inbound>
        <base />
        
        <!-- 1. Managed Identity authentication -->
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
        
        <!-- Response headers for debugging -->
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

### Step 2: Enable LLM Request Logging

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# Diagnostic settings for the API
az apim api diagnostic create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --diagnostic-id "applicationinsights" `
  --logger-id "app-insights-logger" `
  --sampling-percentage 100 `
  --always-log "allErrors"
```

### Step 3: Generate test traffic

```powershell
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

$headers = @{ 
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json" 
}

$questions = @(
    "What is Azure API Management?",
    "Explain how semantic caching works.",
    "What are the benefits of load balancing?",
    "How does token rate limiting work?",
    "What is a managed identity?",
    "Describe the AI Gateway architecture.",
    "What is Azure API Management?",      # Duplicate for cache test
    "How does semantic caching work?"      # Similar for cache test
)

foreach ($question in $questions) {
    Write-Host "Question: $question" -ForegroundColor Cyan
    $body = @{
        messages = @(@{ role = "user"; content = $question })
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

### Step 4: View metrics in Application Insights

Open the Azure Portal and navigate to Application Insights:

1. **Application Insights** → **Metrics**
2. Metric namespace: **AIGateway** (custom namespace)
3. Available metrics:
   - `Prompt Token Count`
   - `Completion Token Count`
   - `Total Token Count`
4. Split by: `Subscription ID`, `Model`, `API ID`

### Step 5: KQL Queries for dashboards

Open **Application Insights → Logs** and run these queries:

#### Token consumption per hour

```kql
customMetrics
| where name startswith "AIGateway"
| summarize TotalTokens = sum(value) by bin(timestamp, 1h), tostring(customDimensions["Subscription ID"])
| render timechart
```

#### Top 10 subscriptions by token consumption

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

#### Errors and rate limits

```kql
requests
| where resultCode == "429" or resultCode startswith "5"
| summarize ErrorCount = count() by bin(timestamp, 5m), resultCode
| render timechart
```

## Expected result

- ✅ Token metrics visible in Application Insights
- ✅ Custom dimensions (Subscription ID, Model) available for filtering
- ✅ KQL queries show token consumption patterns
- ✅ Cache hits vs misses are measurable

## Architecture (Complete)

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
              │ Microsoft       │ │ Microsoft       │
              │ Foundry         │ │ Foundry         │
              │ Sweden Central  │ │ West Europe     │
              │ - gpt-4o-mini   │ │ - gpt-4o-mini   │
              │ - embeddings    │ │ - embeddings    │
              └─────────────────┘ └─────────────────┘
```

## References

- [Token Metrics Policy](https://learn.microsoft.com/azure/api-management/azure-openai-emit-token-metric-policy)
- [LLM Logs & Token Limits](https://learn.microsoft.com/azure/api-management/api-management-howto-llm-logs)
- [Monitoring Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/zero-to-production)

---
**Previous lab:** [← Lab 6 - Load Balancing](../lab-06-load-balancing/README.md)

---

## 🎉 Congratulations!

You have completed the full AI Gateway Workshop! You now have a production-ready AI Gateway with:

- ✅ API Management as a central access point
- ✅ Managed identity authentication (no API keys)
- ✅ Token rate limiting for cost control
- ✅ Semantic caching for cost savings
- ✅ Content safety for safe AI
- ✅ Load balancing for high availability
- ✅ Monitoring with Application Insights
