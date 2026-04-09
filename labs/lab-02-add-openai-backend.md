# Lab 2: Add Microsoft Foundry Backend

> Connect Microsoft Foundry as a backend to your API Management gateway with managed identity authentication.

## 🎯 Goal

Configure APIM to proxy requests to Microsoft Foundry:

- Create a **backend** in APIM pointing to your Foundry endpoint
- Import the **Azure OpenAI REST API specification**
- Apply a **policy** that authenticates using APIM's managed identity
- Create a **subscription** for API key-based access control
- **Test** the end-to-end flow

## Why Managed Identity?

Instead of storing API keys in APIM, we use the managed identity assigned in Lab 1. APIM authenticates to Foundry automatically — no secrets to rotate or leak.

```
Client → (subscription key) → APIM → (managed identity token) → Microsoft Foundry
```

---

## 🛤️ Choose Your Path

---

## 🖥️ Option: Portal

<details>
<summary><strong>Click to expand Portal instructions</strong></summary>

### 1. Create the Backend

1. Go to **API Management** in the [Azure Portal](https://portal.azure.com) and clikc on the resource we just created

   <img src="images/lab-02/API1.png" width="1000"/>

2. Navigate to **APIs → Backends** → **+ Create new backend**

   <img src="images/lab-02/API2.png" width="1000"/>

3. Fill in:
   - **Name**: `foundry-backend`
   - **Backend hosting type**: `Custom URL`
   - **Runtime URL**: `https://<your-foundry-name>.cognitiveservices.azure.com/openai`

      <img src="images/lab-02/API3.png" width="700"/>

4. Click **Create**

### 2. Import the Azure OpenAI API

1. Go to **APIs → APIs** → **+ Add API**
2. Select **Microsoft Foundry**

   <img src="images/lab-02/API4.png" width="1000"/>

3. Select your created AI Service (`ais-aigateway-<uniqueID>`)
4. Select **Review** → **Create**

   <img src="images/lab-02/API5.png" width="500"/>

### 3. Apply the Managed Identity Policy

1. Select your newly imported **Microsoft Foundry API**
2. Click **All operations** in the left panel
3. Click the **</>** icon in the **Inbound processing** section to open the policy editor

   <img src="images/lab-02/API6.png" width="800"/>

4. Replace the entire policy with the content of `policies/managed-identity-auth.xml`:

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
        <set-backend-service backend-id="foundry-backend" />
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

5. Click **Save**

   <img src="images/lab-02/API7.png" width="800"/>

### 4. Create a Test Subscription

APIM uses **subscriptions** to control access to APIs. A subscription provides a pair of keys (primary and secondary) that clients must include in the `Ocp-Apim-Subscription-Key` header when calling the API. Without a valid subscription key, APIM rejects the request with a 401 Unauthorized.

This is how you give consumers (developers, apps, teams) access to your gateway — each gets their own subscription with its own keys, so you can track usage and revoke access per consumer.

1. Go to **APIs → Subscriptions** → **+ Add subscription**

   <img src="images/lab-02/API8.png" width="800"/>

2. Fill in:
   - **Name**: `test-sub`
   - **Display name**: `Test Subscription`
   - **Scope**: `API` 
   - **API**: select the Microsoft Foundry API you created.
3. Click **Create**
4. Click on the subscription → ... → Show/hide keys → copy the **Primary key**

   <img src="images/lab-02/API9.png" width="1000"/>

### 5. Test the API

Now let's verify the full flow works end-to-end: your request goes through APIM, which authenticates to Foundry using its managed identity, and forwards the call to the OpenAI model.

APIM has a built-in **Test** console that lets you send requests directly from the portal — it automatically includes the subscription key, so you don't need an external tool like Postman or curl.

1. Go to **APIs** on the left pannel → select **Microsoft Foundry API**
2. Click the **Test** tab
3. Select the **Creates a completion for the chat message** operation

   <img src="images/lab-02/API10.png" width="1000"/>

4. Set:
   - **deployment-id**: `gpt-4o-mini`
   - **api-version**: `2024-10-21`
5. In the request body:
   ```json
   {
     "messages": [{"role": "user", "content": "Say hello"}],
     "max_tokens": 50
   }
   ```

   <img src="images/lab-02/API11.png" width="700"/>

6. Click **Send**

If you scroll down, you should see a 200 response with a chat completion.

   <img src="images/lab-02/API12.png" width="500"/>
      <img src="images/lab-02/API13.png" width="500"/>

### ✅ Portal Checkpoint

- [ ] Backend `foundry-backend` created
- [ ] Azure OpenAI API imported
- [ ] Managed identity policy applied
- [ ] Test subscription created
- [ ] Test call returns a 200 response

</details>

---

## 💻 Option: CLI

<details>
<summary><strong>Click to expand CLI instructions</strong></summary>

### 1. Set variables

> If you're continuing from Lab 1, your `$RESOURCE_GROUP` and `$LOCATION` are already set.

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$LOCATION = "swedencentral"
```

### 2. Deploy with API configuration enabled

```powershell
cd infra

$policyXml = Get-Content -Path "../policies/managed-identity-auth.xml" -Raw

@{
  '`$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
  contentVersion = '1.0.0.0'
  parameters = @{
    location        = @{ value = $LOCATION }
    enableApiConfig = @{ value = $true }
    policyXml       = @{ value = $policyXml }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-params.json" -Encoding utf8

az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters temp-params.json
```

This deploys:
- **Backend** (`openai-backend`) pointing to your Foundry endpoint
- **API** imported from the Azure OpenAI spec
- **Policy** with managed identity authentication
- **Subscription** (`test-sub`) for API access
- **API diagnostic** connecting to Application Insights

### 3. Test the gateway

```powershell
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$SUBSCRIPTION_ID = az account show --query "id" -o tsv
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

$SUB_KEY = (az rest --method post `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/test-sub/listSecrets?api-version=2024-05-01" `
  | ConvertFrom-Json).primaryKey

$body = @{
    messages = @(@{ role = "user"; content = "What is Azure API Management in one sentence?" })
    model = "gpt-4o-mini"
    max_tokens = 50
} | ConvertTo-Json -Depth 5

$headers = @{
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json"
}

Invoke-RestMethod `
  -Uri "$GATEWAY_URL/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21" `
  -Method POST -Headers $headers -Body $body | ConvertTo-Json -Depth 5
```

### ✅ CLI Checkpoint

You should see a JSON response with `choices[0].message.content` containing an answer.

</details>

---

## 🔧 Option: Bicep

<details>
<summary><strong>Click to expand Bicep instructions</strong></summary>

### 1. Set variables

```powershell
$RESOURCE_GROUP = "rg-aigateway-workshop"
$LOCATION = "swedencentral"
```

### 2. Deploy with API configuration

This deployment enables `enableApiConfig` and applies the managed identity policy.

> **Why a parameters file?** The policy XML is multiline. Passing it inline with `--parameters policyXml="$(…)"` truncates the content in PowerShell, causing an ARM validation error. Writing it to a JSON file first preserves the full XML.

> **Run from the repo root.** The script starts with `cd infra`. If you're already in the `infra` folder, skip that line or run `cd ..` first.

```powershell
cd infra

$policyXml = Get-Content -Path "../policies/managed-identity-auth.xml" -Raw

@{
  '`$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
  contentVersion = '1.0.0.0'
  parameters = @{
    location        = @{ value = $LOCATION }
    enableApiConfig = @{ value = $true }
    policyXml       = @{ value = $policyXml }
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path "temp-params.json" -Encoding utf8

az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters temp-params.json
```

### What gets deployed

In Lab 1, the Bicep template deployed the **base infrastructure**: APIM (BasicV2), Microsoft Foundry (AI Services) with a model deployment, Application Insights, and the RBAC role assignment giving APIM's managed identity access to Foundry. At that point, APIM existed but had no APIs, backends, or policies configured — it was an empty gateway.

This deployment adds the **API layer** on top — everything needed for APIM to actually receive requests and forward them to Foundry.

#### How the flag works

In `main.bicep`, the `enableApiConfig` parameter controls a conditional module deployment:

```bicep
module apimApi 'modules/apim-api.bicep' = if (enableApiConfig) {
  params: {
    apimName:         apim.outputs.name
    foundryEndpoint:  foundryPrimary.outputs.endpoint
    policyXml:        policyXml       // ← passed in from the command line
  }
  dependsOn: [rbacPrimary]            // waits for RBAC to be in place first
}
```

When you set `enableApiConfig=true`, ARM deploys the `apim-api.bicep` module. When `false` (the default), this module is skipped entirely — ARM doesn't even evaluate it.

#### Resources created by `apim-api.bicep`

| Resource | ARM Type | What it does |
|----------|----------|--------------|
| `openai-backend` | `Microsoft.ApiManagement/service/backends` | Tells APIM where to forward requests — the URL is `{foundryEndpoint}openai` (e.g. `https://ais-aigateway-xxx.cognitiveservices.azure.com/openai`) |
| `azure-openai-api` | `Microsoft.ApiManagement/service/apis` | Imports the Azure OpenAI REST API spec from GitHub (`inference.json`). This creates all the operations (chat completions, completions, embeddings, etc.) and sets the API path to `/openai` |
| `policy` | `Microsoft.ApiManagement/service/apis/policies` | Applies the XML policy you pass in (`managed-identity-auth.xml`) at the API level — every operation inherits it |
| `test-sub` | `Microsoft.ApiManagement/service/subscriptions` | Creates a subscription key scoped to this API, so clients can authenticate with `Ocp-Apim-Subscription-Key` |
| `applicationinsights` diagnostic | `Microsoft.ApiManagement/service/apis/diagnostics` | Wires up API-level logging to the Application Insights instance deployed in Lab 1 |

#### What happens under the hood

1. **Backend creation** — ARM creates a backend resource in APIM that stores the Foundry URL. This is just a pointer — no connection is made yet.
2. **API import** — ARM fetches the OpenAI inference spec from `https://raw.githubusercontent.com/.../inference.json` and creates all operations in APIM. The API path is set to `/openai`, which means requests to `https://<apim>.azure-api.net/openai/...` will be handled by this API.
3. **Policy attachment** — The policy XML is applied to "All operations" of the API. ARM base64-encodes and stores it. At runtime, the policy:
   - **`authentication-managed-identity`** — calls the Azure AD token endpoint to get an access token for `https://cognitiveservices.azure.com` using APIM's system-assigned managed identity
   - **`set-header`** — injects `Authorization: Bearer <token>` into the outgoing request
   - **`set-backend-service`** — redirects the request to `openai-backend` (the backend created in step 1)
4. **Subscription creation** — ARM creates a subscription with auto-generated primary and secondary keys, scoped to this API only.
5. **Diagnostic binding** — Links the API to the `app-insights-logger` created in Lab 1, enabling request/response logging and custom metrics.

> **Note:** The `dependsOn: [rbacPrimary]` in `main.bicep` ensures the RBAC role assignment completes before the API module deploys. Without this, the first request through APIM might fail because the managed identity doesn't yet have permission to call Foundry.

### 3. Test the gateway

```powershell
$APIM_NAME = az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv
$SUBSCRIPTION_ID = az account show --query "id" -o tsv
$GATEWAY_URL = az apim show --name $APIM_NAME -g $RESOURCE_GROUP --query "gatewayUrl" -o tsv

$SUB_KEY = (az rest --method post `
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/test-sub/listSecrets?api-version=2024-05-01" `
  | ConvertFrom-Json).primaryKey

$body = @{
    messages = @(@{ role = "user"; content = "What is Azure API Management in one sentence?" })
    model = "gpt-4.1-mini"
    max_tokens = 50
} | ConvertTo-Json -Depth 5

Invoke-RestMethod `
  -Uri "$GATEWAY_URL/openai/deployments/gpt-4.1-mini/chat/completions?api-version=2024-10-21" `
  -Method POST -Headers @{
    "Ocp-Apim-Subscription-Key" = $SUB_KEY
    "Content-Type" = "application/json"
  } -Body $body | ConvertTo-Json -Depth 5
```

### ✅ Bicep Checkpoint

You should see a JSON response with a chat completion from gpt-4.1-mini.

</details>

---

## Expected Result

A successful request through the gateway looks like this:

```json
{
  "id": "chatcmpl-...",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Azure API Management is a fully managed service..."
      }
    }
  ],
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 30,
    "total_tokens": 45
  }
}
```

The `usage` section shows token consumption — we'll use this for rate limiting in the next lab.

---

**Next:** [Lab 3 — Token Rate Limiting →](lab-03-token-rate-limiting.md)
