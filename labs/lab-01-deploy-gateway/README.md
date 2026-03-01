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

### Step 1: Login to Azure

```powershell
# Login to Azure
az login

# Check your active subscription
az account show --query "{name:name, id:id}" -o table

# (Optional) Set the correct subscription
az account set --subscription "<subscription-id>"
```

### Step 2: Create a Resource Group

```powershell
# Set variables
$RESOURCE_GROUP = "rg-aigateway-workshop"
$LOCATION = "swedencentral"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Step 3: Deploy the infrastructure

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
