# Lab 1: Deploy de AI Gateway

> Deploying van Azure API Management (Basicv2) als AI Gateway

## Doel

In deze lab deploy je:
- Een **resource group** voor alle workshop resources
- **Azure API Management** met het Basicv2 SKU
- **Application Insights** voor monitoring

## Waarom Basicv2?

| SKU | Deployment tijd | Kosten | AI Gateway support |
|-----|----------------|--------|-------------------|
| Developer | ~30 min | Laag | ✅ |
| **Basicv2** | **~5-10 min** | **Laag** | **✅** |
| Standardv2 | ~10 min | Medium | ✅ |
| Premium | ~45 min | Hoog | ✅ |

We gebruiken **Basicv2** omdat het snel deployt, goedkoop is, en alle AI Gateway features ondersteunt.

## Stappen

### Stap 1: Login bij Azure

```powershell
# Login bij Azure
az login

# Controleer je actieve subscription
az account show --query "{name:name, id:id}" -o table

# (Optioneel) Stel de juiste subscription in
az account set --subscription "<subscription-id>"
```

### Stap 2: Maak een Resource Group

```powershell
# Variabelen instellen
$RESOURCE_GROUP = "rg-aigateway-workshop"
$LOCATION = "swedencentral"

# Resource group aanmaken
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Stap 3: Deploy de infrastructuur

```powershell
# Navigeer naar de infra folder
cd infra

# Deploy alleen APIM + Application Insights
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters location=$LOCATION `
  --parameters apimPublisherEmail="jouw-email@domein.com" `
  --parameters apimPublisherName="Workshop Deelnemer"
```

> ⏱️ **Let op**: De deployment duurt ~5-10 minuten voor Basicv2.

### Stap 4: Verifieer de deployment

```powershell
# Haal de APIM gateway URL op
az deployment group show `
  --resource-group $RESOURCE_GROUP `
  --name deploy-apim `
  --query "properties.outputs" -o json

# Test of APIM bereikbaar is
$GATEWAY_URL = az apim show `
  --name (az apim list -g $RESOURCE_GROUP --query "[0].name" -o tsv) `
  --resource-group $RESOURCE_GROUP `
  --query "gatewayUrl" -o tsv

Write-Host "Gateway URL: $GATEWAY_URL"
```

## Verwacht resultaat

Na deze lab heb je:
- ✅ Een resource group `rg-aigateway-workshop`
- ✅ API Management (Basicv2) draaiend met een gateway URL
- ✅ Application Insights voor logging en monitoring
- ✅ System-assigned managed identity op APIM

## Architectuur

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

## Referenties

- [APIM Basicv2 SKU](https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview)
- [APIM Bicep Reference](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service)

---
**Volgende lab:** [Lab 2 - Azure OpenAI Backend →](../lab-02-add-openai-backend/README.md)
