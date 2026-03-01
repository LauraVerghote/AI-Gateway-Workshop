# Lab 6: Load Balancing with Retry

> Distribute traffic across multiple Azure OpenAI backends with automatic failover

## Goal

In this lab you will:
- Deploy a **second Azure OpenAI** instance (different region)
- Configure a **backend pool** in APIM
- Set up **automatic retry** on 429 (rate limit) or 503 (unavailable)
- Test failover by overloading one backend

## Background

Load balancing is essential when:
- You **need more quota** than a single OpenAI instance provides
- You want **high availability** (multi-region)
- You want to **spread costs** across multiple instances

```
                    ┌── OpenAI (Sweden Central)  [60% traffic]
Client → APIM ────►│
                    └── OpenAI (West Europe)     [40% traffic]
```

## Steps

### Step 1: Deploy the secondary OpenAI

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"

# Redeploy with secondary OpenAI enabled
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file ../infra/main.bicep `
  --parameters ../infra/main.bicepparam `
  --parameters enableSecondaryOpenAi=true
```

### Step 2: Create the secondary backend in APIM

```powershell
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# Get secondary endpoint
$OAI2_NAME = az cognitiveservices account list -g $RESOURCE_GROUP --query "[?contains(name,'oai-aigateway2')].name" -o tsv
$OAI2_ENDPOINT = az cognitiveservices account show -n $OAI2_NAME -g $RESOURCE_GROUP --query "properties.endpoint" -o tsv

# Create secondary backend
az apim backend create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --backend-id "openai-backend-secondary" `
  --protocol "http" `
  --url "${OAI2_ENDPOINT}openai"
```

### Step 3: Create a Backend Pool (via ARM/Bicep)

Backend pools are configured via Bicep. Add the following:

```bicep
// infra/modules/backend-pool.bicep
param apimServiceName string
param primaryBackendUrl string
param secondaryBackendUrl string

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

resource primaryBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apimService
  name: 'openai-primary'
  properties: {
    protocol: 'http'
    url: primaryBackendUrl
  }
}

resource secondaryBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apimService
  name: 'openai-secondary'
  properties: {
    protocol: 'http'
    url: secondaryBackendUrl
  }
}

resource backendPool 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apimService
  name: 'openai-pool'
  properties: {
    type: 'Pool'
    pool: {
      services: [
        { id: '/backends/${primaryBackend.name}', priority: 1, weight: 60 }
        { id: '/backends/${secondaryBackend.name}', priority: 1, weight: 40 }
      ]
    }
  }
}
```

### Step 4: Apply the Load Balancing Policy

```xml
<!-- policies/load-balancing.xml -->
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
        <!-- Use the backend pool -->
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
        <!-- Show which backend was used -->
        <set-header name="X-Backend-Used" exists-action="override">
            <value>@(context.Request.Url.Host)</value>
        </set-header>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

### Step 5: Apply and test

```powershell
az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/load-balancing.xml"

$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

# Send 10 requests and observe which backend is used
for ($i = 1; $i -le 10; $i++) {
    $body = @{
        messages = @(@{ role = "user"; content = "Hello! Request number $i" })
        model = "gpt-4o-mini"
        max_tokens = 50
    } | ConvertTo-Json -Depth 5

    $response = Invoke-WebRequest `
        -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
        -Method POST `
        -Headers @{ "Ocp-Apim-Subscription-Key" = $SUB_KEY; "Content-Type" = "application/json" } `
        -Body $body

    Write-Host "Request $i - Backend: $($response.Headers['X-Backend-Used'])" -ForegroundColor Cyan
}
```

## Expected result

- ✅ Requests are distributed across two backends (~60/40)
- ✅ On a 429 from backend 1, backend 2 is automatically tried
- ✅ The `X-Backend-Used` header shows which backend was used

## References

- [Backend Pool Load Balancing](https://learn.microsoft.com/azure/api-management/backends?tabs=bicep)
- [Load Balancing Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/backend-pool-load-balancing)
- [Retry Policy](https://learn.microsoft.com/azure/api-management/retry-policy)

---
**Previous lab:** [← Lab 5 - Content Safety](../lab-05-content-safety/README.md)  
**Next lab:** [Lab 7 - Monitoring →](../lab-07-monitoring/README.md)
