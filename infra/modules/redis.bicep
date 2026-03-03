// ===========================================================================
// Azure Cache for Redis Enterprise (required for APIM Semantic Caching)
// Deploys: Redis Enterprise with RediSearch module + configures as APIM
// external cache. RediSearch is required for vector similarity search used
// by the azure-openai-semantic-cache-lookup policy.
//
// NOTE: Redis Enterprise requires Marketplace to be enabled on the
// subscription. If your subscription blocks Marketplace purchases,
// you can either:
//   1. Ask your tenant admin to enable Marketplace
//   2. Switch enableEnterprise to false (disables semantic caching)
// ===========================================================================

@description('Name of the Redis cache')
param name string

@description('Azure region')
param location string

@description('Name of the existing APIM instance')
param apimName string

@description('Deploy Redis Enterprise with RediSearch (requires Marketplace). Set to false for Basic C0.')
param enableEnterprise bool = true

// ===========================================================================
// Option A: Redis Enterprise Cluster (E10) — for semantic caching
// Requires: Marketplace enabled on the subscription
// ===========================================================================
resource redisEnterprise 'Microsoft.Cache/redisEnterprise@2024-09-01-preview' = if (enableEnterprise) {
  name: name
  location: location
  sku: {
    name: 'Enterprise_E10'
    capacity: 2
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2024-09-01-preview' = if (enableEnterprise) {
  parent: redisEnterprise
  name: 'default'
  properties: {
    clientProtocol: 'Encrypted'
    port: 10000
    clusteringPolicy: 'OSSCluster'
    evictionPolicy: 'NoEviction'
    modules: [
      {
        name: 'RediSearch'
      }
    ]
  }
}

// ===========================================================================
// Option B: Redis Basic C0 — when Enterprise is unavailable
// Semantic caching will NOT work, but the infra deploys cleanly.
// Useful for demonstrating the policy structure without full caching.
// ===========================================================================
resource redisBasic 'Microsoft.Cache/redis@2024-03-01' = if (!enableEnterprise) {
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
resource externalCacheEnterprise 'Microsoft.ApiManagement/service/caches@2024-06-01-preview' = if (enableEnterprise) {
  parent: apimService
  name: 'default'
  properties: {
    connectionString: '${redisEnterprise.properties.hostName}:${redisDatabase.properties.port},password=${redisDatabase.listKeys().primaryKey},ssl=True,abortConnect=False'
    useFromLocation: 'default'
    description: 'Redis Enterprise cache for semantic caching'
  }
}

resource externalCacheBasic 'Microsoft.ApiManagement/service/caches@2024-06-01-preview' = if (!enableEnterprise) {
  parent: apimService
  name: 'default'
  properties: {
    connectionString: '${redisBasic.properties.hostName}:${redisBasic.properties.sslPort},password=${redisBasic.listKeys().primaryKey},ssl=True,abortConnect=False'
    useFromLocation: 'default'
    description: 'Redis cache (Basic — semantic caching requires Enterprise)'
  }
}

output id string = enableEnterprise ? redisEnterprise.id : redisBasic.id
output name string = enableEnterprise ? redisEnterprise.name : redisBasic.name
output hostName string = enableEnterprise ? redisEnterprise.properties.hostName : redisBasic.properties.hostName
