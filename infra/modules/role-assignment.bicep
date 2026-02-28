// ===========================================================================
// Role Assignment - Cognitive Services OpenAI User
// ===========================================================================

@description('Principal ID to assign the role to')
param principalId string

@description('Cognitive Services resource ID')
param cognitiveServicesResourceId string

@description('Role definition ID to assign')
param roleDefinitionId string

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cognitiveServicesResourceId, principalId, roleDefinitionId)
  scope: cognitiveServices
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
  }
}

resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: last(split(cognitiveServicesResourceId, '/'))
}
