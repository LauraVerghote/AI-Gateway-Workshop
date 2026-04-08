using 'main.bicep'

// All-Features Deployment
// Deploys the complete AI Gateway with every feature enabled in a single deployment.
// Usage: az deployment group create --resource-group rg-aigateway-workshop --template-file main.bicep --parameters all-features.bicepparam

param location = 'swedencentral'
param apimPublisherEmail = 'workshop@contoso.com'
param apimPublisherName = 'AI Gateway Workshop'
param chatModelName = 'gpt-4o-mini'
param chatModelVersion = '2024-07-18'
param modelCapacity = 30
param enableSecondaryFoundry = true
param secondaryLocation = 'eastus'
param enableApiConfig = true
param enableContentSafety = true
param policyXml = loadTextContent('../policies/demo.xml')
