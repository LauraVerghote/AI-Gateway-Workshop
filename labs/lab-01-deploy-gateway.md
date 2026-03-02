
# Lab 1: Deploy the AI Gateway

> Deploy Azure API Management (Basicv2) as an AI Gateway

## Goal

In this lab you will deploy:
- A **resource group** for all workshop resources
- **Azure API Management** (Basicv2) — the AI Gateway
- **Microsoft Foundry** (Azure AI Services) with gpt-4o-mini and text-embedding-3-small models
- **Application Insights + Log Analytics** for monitoring
- **RBAC role assignment** — gives APIM's managed identity access to Microsoft Foundry

## Why Basicv2?

| SKU | Deployment time | Cost | AI Gateway support |
|-----|-----------------|------|--------------------|
| Developer | ~30 min | Low | ✅ |
| **Basicv2** | **~5-10 min** | **Low** | **✅** |
| Standardv2 | ~10 min | Medium | ✅ |
| Premium | ~45 min | High | ✅ |

We use **Basicv2** because it deploys quickly, is inexpensive, and supports all AI Gateway features.

## Steps

### Step 0: Set up your environment

Create a Python virtual environment so everyone uses the same Azure CLI version, regardless of what's installed on your machine:

```powershell
# From the repository root
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

> **Tip**: You should see `(.venv)` in your terminal prompt when the environment is active. Run `.venv\Scripts\Activate.ps1` again if you open a new terminal.

### Step 1: Login to Azure

First, authenticate with Azure so you can create and manage resources from the command line:

```powershell
az login
```

This opens a browser window where you sign in with your Azure account.

### Step 2: Create a Resource Group

```powershell
# Set variables
$RESOURCE_GROUP = "rg-aigateway-workshop"
$LOCATION = "swedencentral"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Step 3: Deploy the infrastructure

This step uses a Bicep template to deploy the following resources into your resource group:

- **Azure API Management (Basicv2)** — the AI Gateway that will route and manage your API calls
- **Microsoft Foundry** (Azure AI Services) — with two model deployments: `gpt-4o-mini` (chat) and `text-embedding-3-small` (embeddings), plus a **Foundry project** visible in the [Foundry portal](https://ai.azure.com)
- **Application Insights + Log Analytics workspace** — for monitoring, logging, and diagnostics
- **RBAC role assignment** — grants APIM's system-assigned managed identity the *Cognitive Services OpenAI User* role on the Foundry resource, so APIM can authenticate without API keys

```powershell
# Navigate to the infra folder
cd infra

# Deploy the infrastructure
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters location=$LOCATION `
  --parameters apimPublisherEmail="your-email@domain.com" `
  --parameters apimPublisherName="Workshop Participant"
```

> **`apimPublisherEmail` and `apimPublisherName`** are required by Azure when creating an APIM instance. Azure uses them for operational notification emails (e.g. certificate expiry, quota alerts) and as contact information on the developer portal. For this workshop any value works — the defaults in the template (`workshop@contoso.com` / `AI Gateway Workshop`) are fine if you omit these parameters.

> ⏱️ **Note**: The deployment takes ~5-10 minutes for Basicv2.

### Step 4: Verify the deployment

```powershell
# Get the APIM gateway URL
az deployment group show `
  --resource-group $RESOURCE_GROUP `
  --name deploy-apim `
  --query "properties.outputs" -o json

# Test if APIM is reachable
$GATEWAY_URL = az apim show `
  --name (az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv) `
  --resource-group $RESOURCE_GROUP `
  --query "gatewayUrl" -o tsv

Write-Host "Gateway URL: $GATEWAY_URL"
```

You should see output similar to:

```
Gateway URL: https://apim-aigateway-<unique-suffix>.azure-api.net
```

If you see a valid URL, your APIM instance is deployed and reachable. You can also verify in the [Azure Portal](https://portal.azure.com) by navigating to your resource group `rg-aigateway-workshop` — you should see four resources:

| Resource | Type |
|----------|------|
| `apim-aigateway-<suffix>` | API Management service |
| `appi-aigateway-<suffix>` | Application Insights |
| `law-appi-aigateway-<suffix>` | Log Analytics workspace |
| `ais-aigateway-<suffix>` | Microsoft Foundry (AI Services) |

## Expected result

After this lab you will have:
- ✅ A resource group `rg-aigateway-workshop`
- ✅ API Management (Basicv2) running with a gateway URL
- ✅ Microsoft Foundry with gpt-4o-mini and text-embedding-3-small models
- ✅ Application Insights + Log Analytics for monitoring
- ✅ RBAC role assignment — APIM's managed identity can access Microsoft Foundry

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  rg-aigateway-workshop                                       │
│                                                              │
│  ┌───────────────────────┐       ┌────────────────────────┐  │
│  │  API Management       │       │  Microsoft Foundry     │  │
│  │  (Basicv2)            │       │  (AI Services)         │  │
│  │  - Managed Identity ──┼─RBAC─►│  - gpt-4o-mini         │  │
│  │  - Gateway URL        │       │  - text-embedding-3    │  │
│  └───────────────────────┘       │    -small              │  │
│                                  └────────────────────────┘  │
│                                                              │
│  ┌───────────────────────┐       ┌────────────────────────┐  │
│  │  Application Insights │──────►│  Log Analytics         │  │
│  │  (Monitoring)         │       │  workspace             │  │
│  └───────────────────────┘       └────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## References

- [APIM Basicv2 SKU](https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview)
- [APIM Bicep Reference](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service)

---
**Next lab:** [Lab 2 - Foundry Backend →](lab-02-add-openai-backend.md)
