// ===========================================================================
// Main Bicep Template - Azure AI Gateway Workshop
// Deploys: APIM (Basicv2), Microsoft Foundry (AI Services), Application Insights, RBAC
// ===========================================================================

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('APIM publisher email')
param apimPublisherEmail string = 'workshop@contoso.com'

@description('APIM publisher name')
param apimPublisherName string = 'AI Gateway Workshop'

@description('Chat model to deploy')
param chatModelName string = 'gpt-4o-mini'

@description('Chat model version')
param chatModelVersion string = '2024-07-18'

@description('Embedding model to deploy')
param embeddingModelName string = 'text-embedding-3-small'

@description('Embedding model version')
param embeddingModelVersion string = '1'

@description('Tokens per minute for models (in thousands)')
param modelCapacity int = 30

@description('Enable secondary Foundry instance for load balancing lab')
param enableSecondaryFoundry bool = false

@description('Secondary Foundry location')
param secondaryLocation string = 'eastus'

// ===========================================================================
// Application Insights
// ===========================================================================
module appInsights 'modules/app-insights.bicep' = {
  name: 'deploy-app-insights'
  params: {
    location: location
    name: 'appi-aigateway-${uniqueSuffix}'
  }
}

// ===========================================================================
// API Management (Basicv2 SKU)
// ===========================================================================
module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  params: {
    location: location
    name: 'apim-aigateway-${uniqueSuffix}'
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    appInsightsId: appInsights.outputs.id
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
  }
}

// ===========================================================================
// Microsoft Foundry (Primary)
// ===========================================================================
module foundryPrimary 'modules/foundry.bicep' = {
  name: 'deploy-foundry-primary'
  params: {
    location: location
    name: 'ais-aigateway-${uniqueSuffix}'
    modelName: chatModelName
    modelVersion: chatModelVersion
    embeddingModelName: embeddingModelName
    embeddingModelVersion: embeddingModelVersion
    capacity: modelCapacity
  }
}

// ===========================================================================
// Microsoft Foundry (Secondary - for Load Balancing lab)
// ===========================================================================
module foundrySecondary 'modules/foundry.bicep' = if (enableSecondaryFoundry) {
  name: 'deploy-foundry-secondary'
  params: {
    location: secondaryLocation
    name: 'ais-aigateway2-${uniqueSuffix}'
    modelName: chatModelName
    modelVersion: chatModelVersion
    embeddingModelName: embeddingModelName
    embeddingModelVersion: embeddingModelVersion
    capacity: modelCapacity
  }
}

// ===========================================================================
// RBAC: Give APIM Managed Identity access to Foundry (Primary)
// ===========================================================================
module rbacPrimary 'modules/role-assignment.bicep' = {
  name: 'deploy-rbac-primary'
  params: {
    principalId: apim.outputs.principalId
    cognitiveServicesResourceId: foundryPrimary.outputs.id
    // Cognitive Services OpenAI User
    roleDefinitionId: 'a001fd3d-188f-4b5d-821b-7da978bf7442'
  }
}

// ===========================================================================
// RBAC: Give APIM access to Foundry (Secondary)
// ===========================================================================
module rbacSecondary 'modules/role-assignment.bicep' = if (enableSecondaryFoundry) {
  name: 'deploy-rbac-secondary'
  params: {
    principalId: apim.outputs.principalId
    cognitiveServicesResourceId: enableSecondaryFoundry ? foundrySecondary.outputs.id : ''
    roleDefinitionId: 'a001fd3d-188f-4b5d-821b-7da978bf7442'
  }
}

@description('Enable APIM API configuration (backend, API import, policy, subscription)')
param enableApiConfig bool = false

@description('Policy XML content to apply to the Microsoft Foundry API. Override via parameters file.')
param policyXml string = loadTextContent('../policies/base-policy.xml')

@description('Enable embeddings backend for semantic caching')
param enableEmbeddingsBackend bool = false

@description('Deploy Redis Enterprise with RediSearch for semantic caching (requires Marketplace)')
param enableEnterpriseRedis bool = false

@description('Enable content safety backend and RBAC')
param enableContentSafety bool = false

// ===========================================================================
// Azure Cache for Redis (for Semantic Caching lab)
// Required as external cache for APIM semantic cache policies
// ===========================================================================
module redis 'modules/redis.bicep' = if (enableEmbeddingsBackend) {
  name: 'deploy-redis'
  params: {
    location: location
    name: 'redis-aigateway-${uniqueSuffix}'
    apimName: apim.outputs.name
    enableEnterprise: enableEnterpriseRedis
  }
}

// ===========================================================================
// RBAC: Cognitive Services User for Content Safety (Lab 5)
// Broader role than OpenAI User — required for Content Safety API access
// ===========================================================================
module rbacContentSafety 'modules/role-assignment.bicep' = if (enableContentSafety) {
  name: 'deploy-rbac-content-safety'
  params: {
    principalId: apim.outputs.principalId
    cognitiveServicesResourceId: foundryPrimary.outputs.id
    // Cognitive Services User (covers Content Safety API)
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908'
  }
}

// ===========================================================================
// APIM API Configuration (Backend, API, Policy, Subscription)
// Deployed from Lab 2 onwards
// ===========================================================================
module apimApi 'modules/apim-api.bicep' = if (enableApiConfig) {
  name: 'deploy-apim-api'
  params: {
    apimName: apim.outputs.name
    foundryEndpoint: foundryPrimary.outputs.endpoint
    policyXml: policyXml
    embeddingsBackendUrl: enableEmbeddingsBackend ? '${foundryPrimary.outputs.endpoint}openai/deployments/${embeddingModelName}/embeddings' : ''
    contentSafetyBackendUrl: enableContentSafety ? foundryPrimary.outputs.endpoint : ''
    secondaryFoundryEndpoint: enableSecondaryFoundry ? foundrySecondary.outputs.endpoint : ''
  }
  dependsOn: [rbacPrimary, redis, rbacContentSafety, rbacSecondary]
}

// ===========================================================================
// Outputs
// ===========================================================================
output apimGatewayUrl string = apim.outputs.gatewayUrl
output apimName string = apim.outputs.name
output apimPrincipalId string = apim.outputs.principalId
output foundryPrimaryEndpoint string = foundryPrimary.outputs.endpoint
output foundryPrimaryName string = foundryPrimary.outputs.name
output foundrySecondaryEndpoint string = enableSecondaryFoundry ? foundrySecondary.outputs.endpoint : ''
output appInsightsName string = appInsights.outputs.name
output appInsightsConnectionString string = appInsights.outputs.connectionString
