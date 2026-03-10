using './main.bicep'

// =====================================================================
//    CORE — Identify the existing APIM instance and managed identity
// =====================================================================

param apimServiceName = '<your-apim-service-name>'
param managedIdentityName = '<your-managed-identity-name>'

// =====================================================================
//    FEATURE FLAGS — Toggle which configuration sections to apply
//    Set to true to update, false to skip
// =====================================================================

// Policy Fragments
param updatePolicyFragments = true

// APIs
param updateUniversalLLMApi = true
param updateAzureOpenAIApi = true
param updateAzureAISearchApi = false
param updateOpenAIRealtimeApi = false
param updateDocumentIntelligenceApi = false

// LLM Backends & Pools
param updateLLMBackends = true
param updateLLMBackendPools = true
param updateLLMPolicyFragments = true

// Logging / Diagnostics
param updateAppInsightsDiagnostics = true

// Named Values
param updateNamedValues = true

// =====================================================================
//    FEATURE-SPECIFIC PARAMETERS
// =====================================================================

param enablePIIAnonymization = true
param enableAIModelInference = true
param entraAuth = false

// =====================================================================
//    NAMED VALUE PARAMETERS
// =====================================================================

param clientAppId = ' '
// param tenantId — defaults to current tenant
param audience = 'https://cognitiveservices.azure.com/.default'
param aiLanguageServiceUrl = ''
param contentSafetyServiceUrl = ''

// =====================================================================
//    LLM BACKEND CONFIGURATION
//    Define all LLM backends and their supported models.
//    Uncomment and configure the array below to match your environment.
// =====================================================================

param llmBackendConfig = [
  // Example: Azure OpenAI backend
  // {
  //   backendId: 'azure-openai-swedencentral'
  //   backendType: 'azure-openai'
  //   endpoint: 'https://my-openai.openai.azure.com'
  //   authScheme: 'managedIdentity'
  //   supportedModels: [
  //     { name: 'gpt-4o', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2024-08-06' }
  //   ]
  //   priority: 1
  //   weight: 100
  // }
  // Example: AI Foundry backend
  // {
  //   backendId: 'ai-foundry-eastus'
  //   backendType: 'ai-foundry'
  //   endpoint: 'https://my-project.eastus.inference.ml.azure.com'
  //   authScheme: 'managedIdentity'
  //   supportedModels: [
  //     { name: 'gpt-4o-mini', sku: 'GlobalStandard', capacity: 50, modelFormat: 'OpenAI', modelVersion: '2024-07-18' }
  //   ]
  //   priority: 1
  //   weight: 100
  // }
]

// =====================================================================
//    AI SEARCH INSTANCES (only used when updateAzureAISearchApi = true)
// =====================================================================

param aiSearchInstances = [
  // {
  //   name: 'my-search-instance'
  //   description: 'Azure AI Search Service'
  //   url: 'https://my-search.search.windows.net'
  // }
]

// =====================================================================
//    LOGGING / DIAGNOSTICS SETTINGS
//    Customize what is captured in Application Insights and Azure Monitor.
// =====================================================================

param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests:  { messages: 'all', maxSizeInBytes: 262144 }
    responses: { messages: 'all', maxSizeInBytes: 262144 }
  }
}

param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}
