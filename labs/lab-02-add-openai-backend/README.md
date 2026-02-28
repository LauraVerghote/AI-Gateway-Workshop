# Lab 2: Azure OpenAI als Backend toevoegen

> Koppel Azure OpenAI aan je API Management gateway met managed identity authenticatie

## Doel

In deze lab:
- Deploy je **Azure OpenAI** met een GPT-4o-mini en embedding model
- Configureer je een **APIM backend** die naar Azure OpenAI wijst
- Stel je **managed identity authenticatie** in (geen API keys!)
- Importeer je de **Azure OpenAI API** in APIM
- Test je de gateway met een chat completion request

## Stappen

### Stap 1: Deploy Azure OpenAI (als nog niet gedaan)

Als je in Lab 1 de volledige `main.bicep` hebt gedeployed, is OpenAI al beschikbaar. Anders:

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"

# Deploy alles (inclusief OpenAI)
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file ../infra/main.bicep `
  --parameters ../infra/main.bicepparam
```

### Stap 2: Haal namen en endpoints op

```powershell
# APIM naam ophalen
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# OpenAI endpoint ophalen
$OAI_NAME = az cognitiveservices account list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$OAI_ENDPOINT = az cognitiveservices account show -n $OAI_NAME -g $RESOURCE_GROUP --query "properties.endpoint" -o tsv

Write-Host "APIM Name: $APIM_NAME"
Write-Host "OpenAI Name: $OAI_NAME"
Write-Host "OpenAI Endpoint: $OAI_ENDPOINT"
```

### Stap 3: Maak een APIM Backend voor Azure OpenAI

```powershell
# Backend aanmaken in APIM
az apim backend create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --backend-id "openai-backend" `
  --protocol "http" `
  --url "${OAI_ENDPOINT}openai"
```

### Stap 4: Importeer de Azure OpenAI API

```powershell
# Importeer de OpenAI API specificatie
az apim api import `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --path "openai" `
  --display-name "Azure OpenAI API" `
  --specification-format OpenApiJson `
  --specification-url "https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-10-21/inference.json" `
  --subscription-required true
```

### Stap 5: Pas de Managed Identity Policy toe

Maak een policy die managed identity gebruikt in plaats van API keys:

```xml
<!-- policies/managed-identity-auth.xml -->
<policies>
    <inbound>
        <base />
        <!-- Authenticate met APIM managed identity naar Azure OpenAI -->
        <authentication-managed-identity 
            resource="https://cognitiveservices.azure.com" 
            output-token-variable-name="managed-id-access-token" 
            ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
        </set-header>
        <!-- Routeer naar de OpenAI backend -->
        <set-backend-service backend-id="openai-backend" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

Pas de policy toe via CLI:

```powershell
# Policy toepassen op de API
az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/managed-identity-auth.xml"
```

### Stap 6: Test het gateway endpoint

```powershell
# Haal de gateway URL op
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

# Maak een subscription key aan voor testen
az apim subscription create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --subscription-id "test-sub" `
  --display-name "Test Subscription" `
  --scope "/apis/azure-openai-api"

# Haal de subscription key op
$SUB_KEY = az apim subscription show `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --subscription-id "test-sub" `
  --query "primaryKey" -o tsv

# Test met een chat completion request
$body = @{
    messages = @(
        @{
            role = "user"
            content = "Wat is Azure API Management in 1 zin?"
        }
    )
    model = "gpt-4o-mini"
} | ConvertTo-Json -Depth 5

Invoke-RestMethod `
  -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
  -Method POST `
  -Headers @{ "Ocp-Apim-Subscription-Key" = $SUB_KEY; "Content-Type" = "application/json" } `
  -Body $body
```

## Verwacht resultaat

Na deze lab heb je:
- ✅ Azure OpenAI met GPT-4o-mini model gedeployed
- ✅ APIM backend die naar Azure OpenAI wijst
- ✅ Managed identity authenticatie (geen API keys!)
- ✅ OpenAI API geïmporteerd in APIM
- ✅ Werkend chat completion endpoint via de gateway

## Architectuur

```
Client Request
    │
    ▼
┌──────────────────────┐     Managed Identity     ┌──────────────────┐
│  API Management      │ ──────────────────────►  │  Azure OpenAI    │
│  (Gateway)           │     Bearer Token          │  - gpt-4o-mini   │
│  - Policy: Auth MI   │ ◄──────────────────────  │  - embeddings    │
│  - Backend: openai   │     Response              │                  │
└──────────────────────┘                           └──────────────────┘
```

## Referenties

- [Managed Identity Auth Policy](https://learn.microsoft.com/azure/api-management/authentication-managed-identity-policy)
- [Azure OpenAI API in APIM](https://learn.microsoft.com/azure/api-management/azure-openai-api-from-specification)
- [Cognitive Services RBAC Roles](https://learn.microsoft.com/azure/ai-services/openai/how-to/role-based-access-control)

---
**Vorige lab:** [← Lab 1 - Deploy de Gateway](../lab-01-deploy-gateway/README.md)  
**Volgende lab:** [Lab 3 - Token Rate Limiting →](../lab-03-token-rate-limiting/README.md)
