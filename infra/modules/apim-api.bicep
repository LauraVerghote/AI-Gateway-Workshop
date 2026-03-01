// ===========================================================================
// APIM Configuration for Microsoft Foundry
// Deploys: Backend, API, Policy, Subscription
// ===========================================================================

@description('Name of the existing APIM instance')
param apimName string

@description('Microsoft Foundry endpoint URL')
param foundryEndpoint string

@description('Policy XML content to apply to the API')
param policyXml string

// ===========================================================================
// Reference existing APIM instance
// ===========================================================================
resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ===========================================================================
// Backend: Points APIM to the Microsoft Foundry endpoint
// ===========================================================================
resource openAiBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apimService
  name: 'openai-backend'
  properties: {
    url: '${foundryEndpoint}openai'
    protocol: 'http'
  }
}

// ===========================================================================
// API: Import Azure OpenAI-compatible REST API specification (used by Microsoft Foundry)
// ===========================================================================
resource openAiApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apimService
  name: 'azure-openai-api'
  properties: {
    displayName: 'Microsoft Foundry API'
    path: 'openai'
    protocols: ['https']
    subscriptionRequired: true
    format: 'openapi+json-link'
    value: 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-10-21/inference.json'
  }
}

// ===========================================================================
// Policy: Applied to the API (managed identity auth, routing, etc.)
// ===========================================================================
resource openAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: openAiApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: policyXml
  }
  dependsOn: [openAiBackend]
}

// ===========================================================================
// Subscription: Test subscription key scoped to the API
// ===========================================================================
resource testSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = {
  parent: apimService
  name: 'test-sub'
  properties: {
    displayName: 'Test Subscription'
    scope: openAiApi.id
  }
}

// ===========================================================================
// Outputs
// ===========================================================================
output apiId string = openAiApi.id
output subscriptionId string = testSubscription.id
