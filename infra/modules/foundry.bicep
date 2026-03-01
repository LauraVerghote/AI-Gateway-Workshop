// ===========================================================================
// Microsoft Foundry (Azure AI Services) with Model Deployments
// ===========================================================================

@description('Name of the AI Services resource')
param name string

@description('Azure region')
param location string

@description('Chat model name')
param modelName string

@description('Chat model version')
param modelVersion string

@description('Embedding model name')
param embeddingModelName string

@description('Embedding model version')
param embeddingModelVersion string

@description('Model capacity (TPM in thousands)')
param capacity int = 30

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
  }
}

// Chat completion model deployment
resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
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
}

// Embedding model deployment (needed for semantic caching)
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: embeddingModelName
  sku: {
    name: 'GlobalStandard'
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
  }
  dependsOn: [chatDeployment]
}

output id string = aiServices.id
output name string = aiServices.name
output endpoint string = aiServices.properties.endpoint
