using 'main.bicep'

param location = 'swedencentral'
param apimPublisherEmail = 'workshop@contoso.com'
param apimPublisherName = 'AI Gateway Workshop'
param chatModelName = 'gpt-4o-mini'
param chatModelVersion = '2024-07-18'
param embeddingModelName = 'text-embedding-3-small'
param embeddingModelVersion = '1'
param modelCapacity = 30
param enableSecondaryFoundry = false
param secondaryLocation = 'eastus'
