// ===========================================================================
// Microsoft Foundry (Azure AI Services) with Model Deployments + Project
// ===========================================================================

@description('Name of the AI Services resource')
param name string

@description('Azure region')
param location string

@description('Chat model name')
param modelName string

@description('Chat model version')
param modelVersion string

@description('Model capacity (TPM in thousands)')
param capacity int = 30

resource aiServices 'Microsoft.CognitiveServices/accounts@2025-09-01' = {
  name: name
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    allowProjectManagement: true
  }
}

// Foundry project — visible in the Foundry portal (ai.azure.com)
// The project name MUST match the resource name (and custom domain) for the project to be the default.
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-09-01' = {
  parent: aiServices
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Chat completion model deployment
resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-09-01' = {
  parent: aiServices
  name: modelName
  sku: {
    name: 'Standard'
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
  dependsOn: [project]
}

output id string = aiServices.id
output name string = aiServices.name
output endpoint string = aiServices.properties.endpoint
