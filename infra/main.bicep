// ===========================================================================
// Main Bicep Template - Azure AI Gateway Workshop
// Deploys: APIM (Basicv2), Azure OpenAI, Application Insights, RBAC
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

@description('Azure OpenAI model to deploy')
param openAiModelName string = 'gpt-4o-mini'

@description('Azure OpenAI model version')
param openAiModelVersion string = '2024-07-18'

@description('Azure OpenAI embedding model to deploy')
param embeddingModelName string = 'text-embedding-3-small'

@description('Azure OpenAI embedding model version')
param embeddingModelVersion string = '1'

@description('Tokens per minute for OpenAI model (in thousands)')
param openAiCapacity int = 30

@description('Enable secondary OpenAI for load balancing lab')
param enableSecondaryOpenAi bool = false

@description('Secondary OpenAI location')
param secondaryLocation string = 'westeurope'

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
// Azure OpenAI (Primary)
// ===========================================================================
module openAiPrimary 'modules/openai.bicep' = {
  name: 'deploy-openai-primary'
  params: {
    location: location
    name: 'oai-aigateway-${uniqueSuffix}'
    modelName: openAiModelName
    modelVersion: openAiModelVersion
    embeddingModelName: embeddingModelName
    embeddingModelVersion: embeddingModelVersion
    capacity: openAiCapacity
  }
}

// ===========================================================================
// Azure OpenAI (Secondary - for Load Balancing lab)
// ===========================================================================
module openAiSecondary 'modules/openai.bicep' = if (enableSecondaryOpenAi) {
  name: 'deploy-openai-secondary'
  params: {
    location: secondaryLocation
    name: 'oai-aigateway2-${uniqueSuffix}'
    modelName: openAiModelName
    modelVersion: openAiModelVersion
    embeddingModelName: embeddingModelName
    embeddingModelVersion: embeddingModelVersion
    capacity: openAiCapacity
  }
}

// ===========================================================================
// RBAC: Give APIM Managed Identity access to OpenAI (Primary)
// ===========================================================================
module rbacPrimary 'modules/role-assignment.bicep' = {
  name: 'deploy-rbac-primary'
  params: {
    principalId: apim.outputs.principalId
    cognitiveServicesResourceId: openAiPrimary.outputs.id
    // Cognitive Services OpenAI User
    roleDefinitionId: 'a001fd3d-188f-4b5d-821b-7da978bf7442'
  }
}

// ===========================================================================
// RBAC: Give APIM access to OpenAI (Secondary)
// ===========================================================================
module rbacSecondary 'modules/role-assignment.bicep' = if (enableSecondaryOpenAi) {
  name: 'deploy-rbac-secondary'
  params: {
    principalId: apim.outputs.principalId
    cognitiveServicesResourceId: enableSecondaryOpenAi ? openAiSecondary.outputs.id : ''
    roleDefinitionId: 'a001fd3d-188f-4b5d-821b-7da978bf7442'
  }
}

// ===========================================================================
// Outputs
// ===========================================================================
output apimGatewayUrl string = apim.outputs.gatewayUrl
output apimName string = apim.outputs.name
output apimPrincipalId string = apim.outputs.principalId
output openAiPrimaryEndpoint string = openAiPrimary.outputs.endpoint
output openAiPrimaryName string = openAiPrimary.outputs.name
output openAiSecondaryEndpoint string = enableSecondaryOpenAi ? openAiSecondary.outputs.endpoint : ''
output appInsightsName string = appInsights.outputs.name
output appInsightsConnectionString string = appInsights.outputs.connectionString
