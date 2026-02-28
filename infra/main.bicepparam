using 'main.bicep'

param location = 'swedencentral'
param apimPublisherEmail = 'workshop@contoso.com'
param apimPublisherName = 'AI Gateway Workshop'
param openAiModelName = 'gpt-4o-mini'
param openAiModelVersion = '2024-07-18'
param embeddingModelName = 'text-embedding-3-small'
param embeddingModelVersion = '1'
param openAiCapacity = 30
param enableSecondaryOpenAi = false
param secondaryLocation = 'westeurope'
