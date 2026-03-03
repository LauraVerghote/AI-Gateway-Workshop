# Lab 6: Monitoring & Token Metrics

> Track token consumption and request patterns with Application Insights

## Goal

In this lab you will:
- Add the **`azure-openai-emit-token-metric`** policy to track token usage per subscription, model, and client
- Enable **API-level diagnostics** to log full request/response details to Application Insights
- Generate test traffic and **view custom metrics** in the Azure Portal
- Run **KQL queries** to analyze token consumption and error patterns

## Background

### Why monitor your AI Gateway?

Without monitoring, you're flying blind:

- **Cost control** — tokens = money. You need to know which teams, APIs, or models consume the most.
- **Capacity planning** — are you approaching quota limits? Should you add another backend region?
- **Troubleshooting** — when a request fails, you need logs to diagnose whether it's a rate limit, content safety block, or backend error.
- **SLA tracking** — what's the latency, error rate, and availability of your gateway?

### What's already in place

The workshop has incrementally built up the infrastructure. Application Insights and the APIM logger were deployed all the way back in Lab 1:

| Resource | Deployed in | Purpose |
|----------|-------------|---------|
| Application Insights | Lab 1 | Collects telemetry from APIM |
| Log Analytics workspace | Lab 1 | Stores the raw log data behind App Insights |
| APIM Logger (`app-insights-logger`) | Lab 1 | Connects APIM to Application Insights |

What's missing is (1) a policy that **emits token-level metrics** as custom dimensions, and (2) an **API diagnostic** that enables detailed request/response logging.

### How `azure-openai-emit-token-metric` works

This APIM policy works with **Azure OpenAI in Microsoft Foundry models**. It reads the token usage from the API response's `usage` section (`prompt_tokens`, `completion_tokens`, `total_tokens`) and emits them as **custom metrics** to Application Insights. You can attach **dimensions** to slice the data:

| Dimension | Value | What it tracks |
|-----------|-------|----------------|
| `Subscription ID` | `context.Subscription.Id` | Which API consumer (team/app) used the tokens |
| `Client IP` | `context.Request.IpAddress` | Where requests come from |
| `API ID` | `context.Api.Id` | Which API was called |
| `Model` | `context.Request.MatchedParameters["deployment-id"]` | Which model deployment (gpt-4o-mini, etc.) |

The metrics appear under the `azure.applicationinsights` custom namespace in Application Insights Metrics explorer. In the `customMetrics` log table, they appear as `Prompt Tokens`, `Completion Tokens`, and `Total Tokens`.

## Understanding the policy

Open `policies/monitoring.xml` — this is the load balancing policy from Lab 5 with one addition: the `azure-openai-emit-token-metric` block in the `inbound` section.

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
        <!-- Emit token metrics to Application Insights -->
        <azure-openai-emit-token-metric namespace="AIGateway">
            <dimension name="Subscription ID" value="@(context.Subscription.Id)" />
            <dimension name="Client IP" value="@(context.Request.IpAddress)" />
            <dimension name="API ID" value="@(context.Api.Id)" />
            <dimension name="Model" value="@(context.Request.MatchedParameters["deployment-id"])" />
        </azure-openai-emit-token-metric>
    </inbound>
    <backend>
        <!-- Retry on 429 or 503 with failover -->
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

Compared to Lab 5, the only new block is `azure-openai-emit-token-metric`. Everything else (managed identity auth, backend pool, retry logic) stays the same. The metric emission happens in `inbound` because APIM evaluates it after the response comes back — despite being in the inbound section, the token counts are extracted from the response body automatically by the policy.

## Steps

### Step 1: Deploy the monitoring policy

> **If you opened a new terminal since Lab 1**, set your variables again:
> ```powershell
> $RESOURCE_GROUP = "rg-aigateway-workshop"
> $LOCATION = "swedencentral"
> ```

Make sure you're in the `infra/` directory, then deploy:

```powershell
# Read the monitoring policy
$policyXml = Get-Content -Path "../policies/monitoring.xml" -Raw

@{
  '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
  contentVersion = '1.0.0.0'
  parameters = @{
    location                = @{ value = $LOCATION }
    enableApiConfig         = @{ value = $true }
    enableSecondaryFoundry  = @{ value = $true }
    policyXml               = @{ value = $policyXml }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-params.json" -Encoding utf8

# Deploy the updated policy
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters temp-params.json
```

This is a quick deployment (~1-2 minutes) since no new infrastructure is needed — it just updates the APIM policy.

### Step 2: Enable API diagnostics

The APIM logger was created in Lab 1, but it's not yet connected to our API. API diagnostics tell APIM to send detailed request/response information (headers, status codes, duration, backend URL) to Application Insights for every API call. The `metrics = true` setting is critical — without it, the `azure-openai-emit-token-metric` policy won't emit custom metrics.

```powershell
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$SUBSCRIPTION_ID = az account show --query "id" -o tsv

# Build the diagnostic configuration as a JSON file
@{
  properties = @{
    loggerId = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/loggers/app-insights-logger"
    alwaysLog = "allErrors"
    metrics = $true
    sampling = @{ percentage = 100; samplingType = "fixed" }
    frontend = @{
      request  = @{ body = @{ bytes = 0 } }
      response = @{ body = @{ bytes = 0 } }
    }
    backend = @{
      request  = @{ body = @{ bytes = 0 } }
      response = @{ body = @{ bytes = 0 } }
    }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-diagnostic.json" -Encoding utf8

# Create API-level diagnostic — connects the logger to our API
az rest --method put `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/azure-openai-api/diagnostics/applicationinsights?api-version=2024-06-01-preview" `
  --body "@temp-diagnostic.json"
```

Key settings:
- **`metrics = true`** — required for `azure-openai-emit-token-metric` to emit custom metrics to Application Insights
- **`sampling.percentage = 100`** — log every request (in production you'd lower this to reduce costs)
- **`alwaysLog = "allErrors"`** — always log errors regardless of sampling
- **`body.bytes = 0`** — don't log request/response bodies (they can contain sensitive data and are large)

### Step 3: Retrieve the gateway URL and subscription key

```powershell
# Get the gateway URL
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

# Get the test subscription key
$SUB_KEY = (az rest --method post `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/test-sub/listSecrets?api-version=2024-05-01" `
  | ConvertFrom-Json).primaryKey

Write-Host "Gateway URL: $GATEWAY_URL"
Write-Host "Subscription Key: $SUB_KEY"
```

### Step 4: Generate test traffic

Send a batch of varied requests to create meaningful telemetry data:

```powershell
$headers = @{
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json"
}

$questions = @(
    "What is Azure API Management?",
    "Explain how load balancing works.",
    "What are the benefits of rate limiting?",
    "How does token rate limiting work?",
    "What is a managed identity?",
    "Describe the AI Gateway architecture.",
    "What is Azure API Management?",        # Duplicate
    "How does load balancing work?"           # Similar
)

foreach ($question in $questions) {
    Write-Host "Question: $question" -ForegroundColor Cyan
    $body = @{
        messages = @(@{ role = "user"; content = $question })
        model = "gpt-4o-mini"
        max_tokens = 100
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod `
          -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
          -Method POST -Headers $headers -Body $body

        $tokens = $response.usage
        Write-Host "  Prompt: $($tokens.prompt_tokens), Completion: $($tokens.completion_tokens), Total: $($tokens.total_tokens)" -ForegroundColor Green
    } catch {
        Write-Host "  Error: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 1
}
```

Each response shows the token breakdown. The `azure-openai-emit-token-metric` policy reads the token counts from the response and emits them to Application Insights as custom metrics.

> **Note:** You'll notice every response has exactly **100 completion tokens**. That's because the script sets `max_tokens = 100`, which caps each response at that limit. The prompt tokens vary because the questions have different lengths. This is intentional — it generates a predictable amount of token traffic for monitoring purposes.

### Step 5: View metrics in Application Insights

> **Note:** Metrics can take **2-5 minutes** to appear in Application Insights after the requests are sent.

1. Open the [Azure Portal](https://portal.azure.com)
2. Navigate to your **Application Insights** resource (named `appi-aigateway-<suffix>`)
3. Go to **Monitoring → Metrics**
4. Configure the chart:
   - **Metric namespace:** select `azure.applicationinsights` (under "Custom")
   - **Metric:** choose `Prompt Tokens`, `Completion Tokens`, or `Total Tokens`
   - **Aggregation:** `Sum`
   - **Apply splitting:** click "Apply splitting" and split by `Subscription ID` or `Model`

You should see token consumption graphed over time, split by whichever dimension you chose.

### Step 6: Run KQL queries

For more detailed analysis, go to **Application Insights → Monitoring → Logs** and try these queries:

#### Token consumption over time

This shows total tokens used per hour, split by model:

```kql
customMetrics
| where name contains "Tokens"
| where name contains "Total"
| summarize TotalTokens = sum(value) by bin(timestamp, 1h), tostring(customDimensions["Model"])
| render timechart
```

#### Token breakdown by subscription

See which API consumers are using the most tokens:

```kql
customMetrics
| where name == "Total Tokens"
| summarize TotalTokens = sum(value) by tostring(customDimensions["Subscription ID"])
| order by TotalTokens desc
| render barchart
```

#### Request success rate and latency

This uses the built-in `requests` table (populated by the API diagnostic from Step 2):

```kql
requests
| where url contains "openai"
| summarize 
    TotalRequests = count(),
    FailedRequests = countif(toint(resultCode) >= 400),
    AvgDuration = avg(duration),
    P95Duration = percentile(duration, 95)
  by bin(timestamp, 5m)
| extend SuccessRate = round(100.0 * (TotalRequests - FailedRequests) / TotalRequests, 1)
| project timestamp, TotalRequests, SuccessRate, AvgDuration, P95Duration
| render timechart
```

#### Rate limit (429) and error tracking

```kql
requests
| where url contains "openai"
| where toint(resultCode) >= 400
| summarize Count = count() by bin(timestamp, 5m), resultCode
| render timechart
```

> **Tip:** You can pin any of these charts to an **Azure Dashboard** for a permanent monitoring view. Click the pin icon in the top-right of the chart.

## Expected result

After this lab you will have:
- ✅ Token metrics (`Prompt Tokens`, `Completion Tokens`, `Total Tokens`) visible under the `azure.applicationinsights` custom metric namespace in Application Insights
- ✅ Custom dimensions (Subscription ID, Model, Client IP, API ID) available for filtering and splitting
- ✅ API-level diagnostics logging every request to Application Insights
- ✅ KQL queries for token consumption, success rates, and error tracking

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
└──────────┘    │  1. ✅ Managed Identity Auth       (Lab 2)   │
                │  2. ✅ Token Rate Limiting          (Lab 3)   │
                │  3. ✅ Content Safety               (Lab 4)   │
                │  4. ✅ Load Balancing + Retry       (Lab 5)   │
                │  5. ✅ Token Metrics Emission       (Lab 6)   │
                └──────┬───────────────────┬───────────────────┘
                       │                   │
              ┌────────▼────────┐ ┌────────▼────────┐
              │ Microsoft       │ │ Microsoft       │
              │ Foundry         │ │ Foundry         │
              │ Sweden Central  │ │ East US         │
              │ - gpt-4o-mini   │ │ - gpt-4o-mini   │
              └─────────────────┘ └─────────────────┘
```

## References

- [Token Metrics Policy](https://learn.microsoft.com/azure/api-management/azure-openai-emit-token-metric-policy)
- [API Diagnostics](https://learn.microsoft.com/azure/api-management/api-management-howto-use-azure-monitor)
- [KQL Query Language](https://learn.microsoft.com/azure/data-explorer/kusto/query/)
- [Monitoring Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/zero-to-production)

---
**Previous lab:** [← Lab 5 - Load Balancing](lab-05-load-balancing.md)

---

## Congratulations!

You have completed the full AI Gateway Workshop! You now have a production-ready AI Gateway with:

- ✅ **Lab 1** — Infrastructure deployed (APIM, Foundry, App Insights)
- ✅ **Lab 2** — Managed identity authentication (no API keys)
- ✅ **Lab 3** — Token rate limiting for cost control
- ✅ **Lab 4** — Content safety for responsible AI
- ✅ **Lab 5** — Load balancing for high availability
- ✅ **Lab 6** — Monitoring with Application Insights
