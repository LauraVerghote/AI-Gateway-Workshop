# Lab 2: Add Azure OpenAI as Backend

> Connect Azure OpenAI to your API Management gateway with managed identity authentication

## Goal

In this lab you will:
- Configure an **APIM backend** that points to Azure OpenAI
- Set up **managed identity authentication** (no API keys!)
- Import the **Azure OpenAI API** into APIM
- Test the gateway with a chat completion request

## Steps

### Step 1: Set variables and retrieve resource names

Azure OpenAI was already deployed as part of Lab 1. Now retrieve the names and endpoints of your resources:

```powershell
# Get APIM name
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# Get OpenAI endpoint
$OAI_NAME = az cognitiveservices account list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$OAI_ENDPOINT = az cognitiveservices account show -n $OAI_NAME -g $RESOURCE_GROUP --query "properties.endpoint" -o tsv

Write-Host "APIM Name: $APIM_NAME"
Write-Host "OpenAI Name: $OAI_NAME"
Write-Host "OpenAI Endpoint: $OAI_ENDPOINT"
```

### Step 2: Create an APIM Backend for Azure OpenAI

```powershell
# Get your subscription ID
$SUBSCRIPTION_ID = az account show --query "id" -o tsv

# Write the request body to a temp file
@{
  properties = @{
    url = "${OAI_ENDPOINT}openai"
    protocol = "http"
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path backend-body.json

# Create backend in APIM via REST API
az rest --method put `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/backends/openai-backend?api-version=2024-05-01" `
  --body "@backend-body.json"

# Clean up
Remove-Item backend-body.json
```

### Step 3: Import the Azure OpenAI API

```powershell
# Import the OpenAI API specification
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

### Step 4: Apply the Managed Identity Policy

The repository already includes a policy file at `policies/managed-identity-auth.xml` that configures APIM to authenticate with Azure OpenAI using its managed identity instead of API keys. Here's what it does:

- **`authentication-managed-identity`** — requests a token from Entra ID for the `cognitiveservices.azure.com` resource
- **`set-header Authorization`** — adds the token as a Bearer header to the outgoing request
- **`set-backend-service`** — routes the request to the `openai-backend` you created in Step 2

Apply this policy to the imported API:

```powershell
# Apply policy to the API
az apim api policy create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --api-id "azure-openai-api" `
  --xml-file "../../policies/managed-identity-auth.xml"
```

### Step 5: Test the gateway endpoint

```powershell
# Get the gateway URL
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

# Create a subscription key for testing
az apim subscription create `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --subscription-id "test-sub" `
  --display-name "Test Subscription" `
  --scope "/apis/azure-openai-api"

# Get the subscription key
$SUB_KEY = az apim subscription show `
  --resource-group $RESOURCE_GROUP `
  --service-name $APIM_NAME `
  --subscription-id "test-sub" `
  --query "primaryKey" -o tsv

# Test with a chat completion request
$body = @{
    messages = @(
        @{
            role = "user"
            content = "What is Azure API Management in one sentence?"
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

## Expected result

After this lab you will have:
- ✅ Azure OpenAI with GPT-4o-mini model deployed
- ✅ APIM backend pointing to Azure OpenAI
- ✅ Managed identity authentication (no API keys!)
- ✅ OpenAI API imported into APIM
- ✅ Working chat completion endpoint through the gateway

## Architecture

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

## References

- [Managed Identity Auth Policy](https://learn.microsoft.com/azure/api-management/authentication-managed-identity-policy)
- [Azure OpenAI API in APIM](https://learn.microsoft.com/azure/api-management/azure-openai-api-from-specification)
- [Cognitive Services RBAC Roles](https://learn.microsoft.com/azure/ai-services/openai/how-to/role-based-access-control)

---
**Previous lab:** [← Lab 1 - Deploy the Gateway](../lab-01-deploy-gateway/README.md)  
**Next lab:** [Lab 3 - Token Rate Limiting →](../lab-03-token-rate-limiting/README.md)
