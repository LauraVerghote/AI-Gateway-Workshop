# Lab 2: Add Microsoft Foundry as Backend

> Connect Microsoft Foundry to your API Management gateway with managed identity authentication

## Goal

In this lab you will configure APIM to act as a gateway in front of Microsoft Foundry. By the end, you'll have a working endpoint where clients send requests to APIM, and APIM authenticates to Microsoft Foundry using its managed identity — no API keys involved.

Specifically, this lab deploys:
- An **APIM backend** — tells APIM where Microsoft Foundry lives
- An **API definition** — imports the Azure OpenAI-compatible REST API spec so APIM knows the available operations (chat completions, embeddings, etc.). Microsoft Foundry uses the same API format.
- A **policy** — intercepts every request to get a managed identity token, set the Authorization header, and route to the backend
- A **subscription** — creates a test API key so you can call the gateway

## What is a policy?

An APIM policy is an XML document that runs on every request. It has four sections:

| Section | When it runs | What it does |
|---------|-------------|-------------|
| `inbound` | Before the request reaches the backend | Authentication, rate limiting, caching, header manipulation |
| `backend` | During the call to the backend | Forwarding configuration |
| `outbound` | After the backend responds | Response transformation, header injection |
| `on-error` | When something fails | Error handling |

In this lab, the policy (`policies/managed-identity-auth.xml`) does three things in the `inbound` section:

1. **`authentication-managed-identity`** — asks Entra ID for a token scoped to `cognitiveservices.azure.com` using APIM's system-assigned managed identity
2. **`set-header Authorization`** — puts that token in the `Authorization: Bearer <token>` header
3. **`set-backend-service`** — routes the request to the `openai-backend`

This means clients never need a Microsoft Foundry API key — they authenticate to APIM with a subscription key, and APIM handles the Microsoft Foundry authentication automatically.

## Understanding the Bicep

Open `infra/modules/apim-api.bicep` to see the four resources being deployed. Here's what each one does:

### 1. Backend (`openai-backend`)
```
APIM Backend → points to → https://<your-foundry>.openai.azure.com/openai
```
This tells APIM where to forward requests. When a policy says `set-backend-service backend-id="openai-backend"`, APIM looks up this backend to get the URL.

### 2. API (`azure-openai-api`)
Imports the official [Azure OpenAI REST API specification](https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-10-21/inference.json) from Microsoft. This registers all operations (chat completions, embeddings, image generation, etc.) so APIM can validate and route requests correctly. The API is exposed at the `/openai` path on your gateway. Microsoft Foundry uses the same OpenAI-compatible API spec.

### 3. Policy (`managed-identity-auth`)
The XML content from `policies/managed-identity-auth.xml` is attached to the API. Every request to `/openai/*` passes through this policy before reaching Microsoft Foundry.

### 4. Subscription (`test-sub`)
Creates an API key scoped to the API. Clients must include this key in the `Ocp-Apim-Subscription-Key` header to call the gateway. This is how APIM controls who can access your AI endpoints.

## Steps

### Step 1: Review the policy file

Before deploying, take a look at the policy that will be applied. Open `policies/managed-identity-auth.xml`:

```xml
<policies>
    <inbound>
        <base />
        <authentication-managed-identity 
            resource="https://cognitiveservices.azure.com" 
            output-token-variable-name="managed-id-access-token" 
            ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["managed-id-access-token"])</value>
        </set-header>
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

This is what runs on every request to your API through APIM.

### Step 2: Deploy the APIM configuration

Run the Bicep deployment with `enableApiConfig=true` to deploy the backend, API, policy, and subscription. We use a JSON parameters file to safely pass the policy XML content (inline parameters can break due to PowerShell XML escaping):

```powershell
# Read the policy XML and create a parameters file
$policyXml = Get-Content -Path "../policies/managed-identity-auth.xml" -Raw

@{
  '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
  contentVersion = '1.0.0.0'
  parameters = @{
    location       = @{ value = $LOCATION }
    enableApiConfig = @{ value = $true }
    policyXml      = @{ value = $policyXml }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-params.json" -Encoding utf8

# Deploy APIM API configuration
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters temp-params.json
```

This deploys four new resources inside your existing APIM instance:

| Resource | Type | Purpose |
|----------|------|---------|
| `openai-backend` | APIM Backend | Points to your Microsoft Foundry endpoint |
| `azure-openai-api` | APIM API | Imports the OpenAI-compatible REST API spec |
| `policy` | APIM API Policy | Managed identity auth + routing |
| `test-sub` | APIM Subscription | Test API key scoped to the API |

> ⏱️ **Note**: This deployment is quick (~1-2 minutes) since APIM is already running.

### Step 3: Retrieve the gateway URL and subscription key

```powershell
# Get APIM name
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv

# Get the gateway URL
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

# Get your subscription ID
$SUBSCRIPTION_ID = az account show --query "id" -o tsv

# Get the test subscription key
$SUB_KEY = (az rest --method post `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/test-sub/listSecrets?api-version=2024-05-01" `
  | ConvertFrom-Json).primaryKey

Write-Host "Gateway URL: $GATEWAY_URL"
Write-Host "Subscription Key: $SUB_KEY"
```

### Step 4: Test the gateway endpoint

Send a chat completion request through the gateway. This tests the full chain: your request hits APIM, the policy authenticates with managed identity, and the request is forwarded to Microsoft Foundry.

```powershell
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

If everything is working, you should see a response like this:

```
id      : chatcmpl-abc123...
object  : chat.completion
model   : gpt-4o-mini-2024-07-18
choices : {@{index=0; message=; finish_reason=stop}}
usage   : @{prompt_tokens=15; completion_tokens=30; total_tokens=45}
```

The `choices[0].message.content` field contains the AI's answer. This confirms the full chain is working:

**Client → APIM (subscription key) → Policy (managed identity token) → Microsoft Foundry → Response**

## Expected result

After this lab you will have:
- ✅ APIM backend pointing to Microsoft Foundry
- ✅ Azure OpenAI-compatible REST API imported into APIM
- ✅ Managed identity authentication policy (no API keys to Microsoft Foundry!)
- ✅ Test subscription key for calling the gateway
- ✅ Working chat completion endpoint through the gateway

## Architecture

```
Client Request
    │
    ▼
┌──────────────────────┐     Managed Identity     ┌──────────────────┐
│  API Management      │ ──────────────────►  │  Microsoft       │
│  (Gateway)           │     Bearer Token          │  Foundry          │
│  - Policy: Auth MI   │ ◄──────────────────  │  - gpt-4o-mini   │
│  - Backend: openai   │     Response              │  - embeddings    │
└──────────────────────┘                           └──────────────────┘
```

## References

- [Managed Identity Auth Policy](https://learn.microsoft.com/azure/api-management/authentication-managed-identity-policy)
- [Azure OpenAI API in APIM](https://learn.microsoft.com/azure/api-management/azure-openai-api-from-specification)
- [Cognitive Services RBAC Roles](https://learn.microsoft.com/azure/ai-services/openai/how-to/role-based-access-control)

---
**Previous lab:** [← Lab 1 - Deploy the Gateway](../lab-01-deploy-gateway/README.md)  
**Next lab:** [Lab 3 - Token Rate Limiting →](../lab-03-token-rate-limiting/README.md)
