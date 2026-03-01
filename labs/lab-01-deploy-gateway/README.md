
# Lab 1: Deploy the AI Gateway

> Deploy Azure API Management (Basicv2) as an AI Gateway

## Goal

In this lab you will deploy:
- A **resource group** for all workshop resources
- **Azure API Management** with the Basicv2 SKU
- **Application Insights** for monitoring

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
- **Application Insights + Log Analytics workspace** — for monitoring, logging, and diagnostics
- **System-assigned Managed Identity** on APIM — used later to authenticate securely to Azure OpenAI without keys

```powershell
# Navigate to the infra folder
cd infra

# Deploy only APIM + Application Insights
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters location=$LOCATION `
  --parameters apimPublisherEmail="your-email@domain.com" `
  --parameters apimPublisherName="Workshop Participant"
```

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

## Expected result

After this lab you will have:
- ✅ A resource group `rg-aigateway-workshop`
- ✅ API Management (Basicv2) running with a gateway URL
- ✅ Application Insights for logging and monitoring
- ✅ System-assigned managed identity on APIM

## Architecture

```
┌─────────────────────────────────┐
│     rg-aigateway-workshop       │
│                                 │
│  ┌───────────────────────────┐  │
│  │  API Management (Basicv2) │  │
│  │  - Managed Identity       │  │
│  │  - Gateway URL            │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │  Application Insights     │  │
│  │  + Log Analytics          │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

## References

- [APIM Basicv2 SKU](https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview)
- [APIM Bicep Reference](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service)

---
**Next lab:** [Lab 2 - Azure OpenAI Backend →](../lab-02-add-openai-backend/README.md)
