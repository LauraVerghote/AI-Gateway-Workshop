// ===========================================================================
// Azure API Management - Basicv2 SKU (AI Gateway)
// ===========================================================================

@description('Name of the APIM instance')
param name string

@description('Azure region')
param location string

@description('Publisher email')
param publisherEmail string

@description('Publisher name')
param publisherName string

@description('Application Insights resource ID')
param appInsightsId string

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string

// NOTE: Using 2024-06-01-preview because Basicv2 SKU support currently requires this preview API version.
//       Update to the latest stable (GA) API version once Basicv2 is available there.
resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: name
  location: location
  sku: {
    name: 'Basicv2'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Application Insights logger
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = {
  parent: apimService
  name: 'app-insights-logger'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appInsightsId
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
  }
}

output id string = apimService.id
output name string = apimService.name
output gatewayUrl string = apimService.properties.gatewayUrl
output principalId string = apimService.identity.principalId
