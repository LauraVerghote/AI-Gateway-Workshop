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

@description('URL for the embeddings backend (optional, for semantic caching)')
param embeddingsBackendUrl string = ''

@description('URL for the content safety backend (optional, for content safety lab)')
param contentSafetyBackendUrl string = ''

@description('Secondary Foundry endpoint URL (for load balancing lab)')
param secondaryFoundryEndpoint string = ''

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
// Embeddings Backend (optional, for semantic caching lab)
// Points to the specific embedding model deployment
// ===========================================================================
resource embeddingsBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (!empty(embeddingsBackendUrl)) {
  parent: apimService
  name: 'embeddings-backend'
  properties: {
    url: embeddingsBackendUrl
    protocol: 'http'
  }
}

// ===========================================================================
// Content Safety Backend (optional, for content safety lab)
// Points to the Foundry endpoint for Content Safety API calls
// ===========================================================================
resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (!empty(contentSafetyBackendUrl)) {
  parent: apimService
  name: 'content-safety-backend'
  properties: {
    url: contentSafetyBackendUrl
    protocol: 'http'
  }
}

// ===========================================================================
// Secondary Backend (for load balancing lab)
// Points to a second Microsoft Foundry instance in a different region
// ===========================================================================
resource secondaryBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (!empty(secondaryFoundryEndpoint)) {
  parent: apimService
  name: 'openai-backend-secondary'
  properties: {
    url: '${secondaryFoundryEndpoint}openai'
    protocol: 'http'
  }
}

// ===========================================================================
// Backend Pool (for load balancing lab)
// Distributes traffic across primary and secondary backends with weighted routing
// ===========================================================================
resource backendPool 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (!empty(secondaryFoundryEndpoint)) {
  parent: apimService
  name: 'openai-pool'
  properties: {
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/backends/${openAiBackend.name}'
          priority: 1
          weight: 60
        }
        {
          id: '/backends/${secondaryBackend.name}'
          priority: 1
          weight: 40
        }
      ]
    }
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
    format: 'rawxml'
    value: policyXml
  }
  dependsOn: [openAiBackend, embeddingsBackend, contentSafetyBackend, secondaryBackend, backendPool]
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
