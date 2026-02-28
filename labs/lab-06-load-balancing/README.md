# Lab 6: Load Balancing met Retry

> Verdeel verkeer over meerdere Azure OpenAI backends met automatische failover

## Doel

In deze lab:
- Deploy je een **tweede Azure OpenAI** instance (andere regio)
- Configureer je een **backend pool** in APIM
- Stel je **automatische retry** in bij 429 (rate limit) of 503 (unavailable)
- Test je failover door één backend te overbelasten

## Achtergrond

Load balancing is essentieel wanneer:
- Je **meer quota** nodig hebt dan één OpenAI instance biedt
- Je **hoge beschikbaarheid** wilt (multi-region)
- Je **kosten wilt spreiden** over meerdere instances

```
                    ┌── OpenAI (Sweden Central)  [60% traffic]
Client → APIM ────►│
                    └── OpenAI (West Europe)     [40% traffic]
```

## Stappen

### Stap 1: Deploy de secundaire OpenAI

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"

# Herdeployment met secondary OpenAI enabled
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file ../infra/main.bicep `
  --parameters ../infra/main.bicepparam `
  --parameters enableSecondaryOpenAi=true
```

### Stap 2: Maak de secundaire backend in APIM

```powershell
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# Haal secondary endpoint op
$OAI2_NAME = az cognitiveservices account list -g $RESOURCE_GROUP --query "[?contains(name,'oai-aigateway2')].name" -o tsv
$OAI2_ENDPOINT = az cognitiveservices account show -n $OAI2_NAME -g $RESOURCE_GROUP --query "properties.endpoint" -o tsv

# Maak secondary backend
az apim backend create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --backend-id "openai-backend-secondary" `
  --protocol "http" `
  --url "${OAI2_ENDPOINT}openai"
```

### Stap 3: Maak een Backend Pool (via ARM/Bicep)

Backend pools worden geconfigureerd via Bicep. Voeg dit toe:

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

### Stap 4: Pas de Load Balancing Policy toe

```xml
<!-- policies/load-balancing.xml -->
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
        <!-- Gebruik de backend pool -->
        <set-backend-service backend-id="openai-pool" />
    </inbound>
    <backend>
        <!-- Retry bij 429 (rate limit) of 503 (service unavailable) -->
        <retry count="2" interval="0" first-fast-retry="true" 
            condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode == 503)">
            <set-backend-service backend-id="openai-pool" />
            <forward-request buffer-request-body="true" />
        </retry>
    </backend>
    <outbound>
        <!-- Toon welke backend is gebruikt -->
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

### Stap 5: Apply en test

```powershell
az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/load-balancing.xml"

$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv
$SUB_KEY = az apim subscription show -g $RESOURCE_GROUP --service-name $APIM_NAME --subscription-id "test-sub" --query "primaryKey" -o tsv

# Stuur 10 requests en observeer welke backend wordt gebruikt
for ($i = 1; $i -le 10; $i++) {
    $body = @{
        messages = @(@{ role = "user"; content = "Hallo! Request nummer $i" })
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

## Verwacht resultaat

- ✅ Requests worden verdeeld over twee backends (~60/40)
- ✅ Bij een 429 op backend 1 wordt automatisch backend 2 geprobeerd
- ✅ De `X-Backend-Used` header toont welke backend is gebruikt

## Referenties

- [Backend Pool Load Balancing](https://learn.microsoft.com/azure/api-management/backends?tabs=bicep)
- [Load Balancing Lab](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/backend-pool-load-balancing)
- [Retry Policy](https://learn.microsoft.com/azure/api-management/retry-policy)

---
**Vorige lab:** [← Lab 5 - Content Safety](../lab-05-content-safety/README.md)  
**Volgende lab:** [Lab 7 - Monitoring →](../lab-07-monitoring/README.md)
