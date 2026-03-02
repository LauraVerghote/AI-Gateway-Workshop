// ===========================================================================
// Azure Cache for Redis (required for APIM Semantic Caching)
// Deploys: Redis instance + configures it as APIM external cache
// ===========================================================================

@description('Name of the Redis cache')
param name string

@description('Azure region')
param location string

@description('Name of the existing APIM instance')
param apimName string

// ===========================================================================
// Azure Cache for Redis (Basic C0 tier — sufficient for workshop)
// ===========================================================================
resource redis 'Microsoft.Cache/redis@2024-03-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
  }
}

// ===========================================================================
// Reference existing APIM instance
// ===========================================================================
resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ===========================================================================
// Configure Redis as APIM external cache
// ===========================================================================
resource externalCache 'Microsoft.ApiManagement/service/caches@2024-06-01-preview' = {
  parent: apimService
  name: 'default'
  properties: {
    connectionString: '${redis.properties.hostName}:${redis.properties.sslPort},password=${redis.listKeys().primaryKey},ssl=True,abortConnect=False'
    useFromLocation: 'default'
    description: 'Redis cache for semantic caching'
  }
}

output id string = redis.id
output name string = redis.name
output hostName string = redis.properties.hostName
