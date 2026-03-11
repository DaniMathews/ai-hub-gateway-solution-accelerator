targetScope = 'subscription'

// ============================================================================
// Agent Access Contract Request - Bicep Entry Point
// ============================================================================
// This module accepts an Agent Access Contract Request (JSON) and automatically
// generates the APIM policy XML and deployment parameters needed to deploy an
// access contract using the existing Citadel Access Contracts infrastructure.
//
// Usage in .bicepparam:
//   using 'main.bicep'
//   param contractRequest = loadJsonContent('access-contract-request.json')
//
// Deployment:
//   az deployment sub create \
//     --name <deployment-name> \
//     --location <region> \
//     --template-file base-access-contract-request/main.bicep \
//     --parameters <path-to>/main.bicepparam
// ============================================================================

@description('Agent Access Contract Request configuration loaded from JSON file')
param contractRequest object

// ============================================================================
// EXTRACT CONFIGURATION SECTIONS
// ============================================================================

var contractInfo = contractRequest.contractInfo
var infra = contractRequest.infrastructure
var policiesConfig = contractRequest.?policies ?? {}
var servicesList = contractRequest.services

// --- Infrastructure ---
var apimConfig = infra.apim

var kvEnabled = infra.?keyVault.?enabled ?? false
var kvConfig = {
  subscriptionId: kvEnabled ? infra.keyVault.subscriptionId : '00000000-0000-0000-0000-000000000000'
  resourceGroupName: kvEnabled ? infra.keyVault.resourceGroupName : 'placeholder'
  name: kvEnabled ? infra.keyVault.name : 'placeholder'
}

var foundryEnabled = infra.?foundry.?enabled ?? false
var foundryCoords = {
  subscriptionId: foundryEnabled ? infra.foundry.subscriptionId : '00000000-0000-0000-0000-000000000000'
  resourceGroupName: foundryEnabled ? infra.foundry.resourceGroupName : 'placeholder'
  accountName: foundryEnabled ? infra.foundry.accountName : 'placeholder'
  projectName: foundryEnabled ? infra.foundry.projectName : 'placeholder'
}

// Foundry connection config with defaults
var foundryConfigDefaults = {
  connectionNamePrefix: ''
  deploymentInPath: 'false'
  isSharedToAll: false
  inferenceAPIVersion: ''
  deploymentAPIVersion: ''
  staticModels: []
  listModelsEndpoint: ''
  getModelEndpoint: ''
  deploymentProvider: ''
  customHeaders: {}
  authConfig: {}
}
var foundryConfigFinal = union(foundryConfigDefaults, infra.?foundry.?config ?? {})

// ============================================================================
// LOAD POLICY SNIPPET TEMPLATES
// ============================================================================

var snippetModelExtraction = loadTextContent('snippets/model-extraction.xml')
var snippetModelAccess = loadTextContent('snippets/model-access.xml')
var snippetCapacitySubLevel = loadTextContent('snippets/capacity-subscription-level.xml')
var snippetCapacityPerModelWrapper = loadTextContent('snippets/capacity-per-model-wrapper.xml')
var snippetCapacityPerModelEntry = loadTextContent('snippets/capacity-per-model-entry.xml')
var snippetContentSafety = loadTextContent('snippets/content-safety.xml')
var snippetContentSafetyCategory = loadTextContent('snippets/content-safety-category.xml')
var snippetPiiAnonymizationInbound = loadTextContent('snippets/pii-anonymization-inbound.xml')
var snippetPiiBlockingInbound = loadTextContent('snippets/pii-blocking-inbound.xml')
var snippetPiiRegexEntry = loadTextContent('snippets/pii-regex-entry.xml')
var snippetPiiDeanonymizationOutbound = loadTextContent('snippets/pii-deanonymization-outbound.xml')
var snippetPiiStateSaving = loadTextContent('snippets/pii-state-saving.xml')
var snippetUsageTracking = loadTextContent('snippets/usage-tracking.xml')
var snippetAlertsThrottling = loadTextContent('snippets/alerts-throttling.xml')
var snippetJwtAuth = loadTextContent('snippets/jwt-auth.xml')
var masterTemplate = loadTextContent('policy-master-template.xml')

// ============================================================================
// POLICY CONFIGURATION FLAGS
// ============================================================================

// --- Model Access ---
var modelAccessEnabled = policiesConfig.?modelAccess.?enabled ?? false
var allowedModels = modelAccessEnabled ? join(policiesConfig.modelAccess.allowedModels, ',') : ''

// --- Capacity Management ---
var capacityEnabled = policiesConfig.?capacityManagement.?enabled ?? false
var capacityMode = policiesConfig.?capacityManagement.?mode ?? 'subscription-level'

// --- Content Safety ---
var contentSafetyEnabled = policiesConfig.?contentSafety.?enabled ?? false
var shieldPrompt = policiesConfig.?contentSafety.?shieldPrompt ?? true
var safetyCategories = policiesConfig.?contentSafety.?categories ?? []

// --- PII Handling ---
var piiEnabled = policiesConfig.?piiHandling.?enabled ?? false
var piiMode = policiesConfig.?piiHandling.?mode ?? 'anonymize'
var piiConfidence = string(policiesConfig.?piiHandling.?confidenceThreshold ?? '0.8')
var piiExclusions = policiesConfig.?piiHandling.?entityCategoryExclusions ?? ''
var piiLanguage = policiesConfig.?piiHandling.?language ?? 'en'
var piiStateSavingEnabled = policiesConfig.?piiHandling.?stateSaving ?? false
var piiRegexPatterns = policiesConfig.?piiHandling.?customRegexPatterns ?? []

// --- Usage Tracking ---
var usageEnabled = policiesConfig.?usageTracking.?enabled ?? false
var appIdHeader = policiesConfig.?usageTracking.?appIdHeader ?? 'x-app-id'
var cd1Header = policiesConfig.?usageTracking.?customDimension1.?header ?? ''
var cd1Default = policiesConfig.?usageTracking.?customDimension1.?default ?? ''
var cd2Header = policiesConfig.?usageTracking.?customDimension2.?header ?? ''
var cd2Default = policiesConfig.?usageTracking.?customDimension2.?default ?? ''

// --- Alerts ---
var alertsEnabled = policiesConfig.?alerts.?enabled ?? false
var throttlingEvents = policiesConfig.?alerts.?throttlingEvents ?? false

// --- JWT Authentication ---
var jwtAuthEnabled = policiesConfig.?jwtAuth.?enabled ?? false

// --- Derived flags ---
var needsModelExtraction = modelAccessEnabled || (capacityEnabled && capacityMode == 'per-model')

// ============================================================================
// BUILD INBOUND POLICY SECTIONS
// ============================================================================

// --- Model Extraction (shared dependency for model access + per-model capacity) ---
var modelExtractionXml = needsModelExtraction ? snippetModelExtraction : ''

// --- Model Access Control ---
var modelAccessXml = modelAccessEnabled
  ? replace(snippetModelAccess, '{{ALLOWED_MODELS}}', allowedModels)
  : ''

// --- Capacity: Subscription Level ---
var subLevelConfig = policiesConfig.?capacityManagement.?subscriptionLevel ?? {
  tokensPerMinute: 1000
  tokenQuota: 100000
  tokenQuotaPeriod: 'Monthly'
}
var capacitySubLevelXml = capacityEnabled && capacityMode == 'subscription-level'
  ? replace(
      replace(
        replace(snippetCapacitySubLevel, '{{TPM}}', string(subLevelConfig.tokensPerMinute)),
        '{{QUOTA}}', string(subLevelConfig.tokenQuota)),
      '{{QUOTA_PERIOD}}', subLevelConfig.?tokenQuotaPeriod ?? 'Monthly')
  : ''

// --- Capacity: Per Model ---
var perModelList = policiesConfig.?capacityManagement.?perModel ?? []
var defaultModelCfg = policiesConfig.?capacityManagement.?defaultModel ?? {
  tokensPerMinute: 100
  tokenQuota: 10000
  tokenQuotaPeriod: 'Monthly'
}

var perModelEntries = [for m in perModelList: replace(
  replace(
    replace(
      replace(snippetCapacityPerModelEntry, '{{MODEL_NAME}}', m.model),
      '{{TPM}}', string(m.tokensPerMinute)),
    '{{QUOTA}}', string(m.?tokenQuota ?? 0)),
  '{{QUOTA_PERIOD}}', m.?tokenQuotaPeriod ?? 'Monthly')]
var perModelEntriesXml = join(perModelEntries, '\n')

var capacityPerModelXml = capacityEnabled && capacityMode == 'per-model'
  ? replace(
      replace(
        replace(
          replace(snippetCapacityPerModelWrapper, '{{PER_MODEL_ENTRIES}}', perModelEntriesXml),
          '{{DEFAULT_TPM}}', string(defaultModelCfg.tokensPerMinute)),
        '{{DEFAULT_QUOTA}}', string(defaultModelCfg.?tokenQuota ?? 10000)),
      '{{DEFAULT_QUOTA_PERIOD}}', defaultModelCfg.?tokenQuotaPeriod ?? 'Monthly')
  : ''

var capacityXml = capacityEnabled
  ? (capacityMode == 'per-model' ? capacityPerModelXml : capacitySubLevelXml)
  : ''

// --- Content Safety ---
var categoryEntries = [for cat in safetyCategories: replace(
  replace(snippetContentSafetyCategory, '{{CAT_NAME}}', cat.name),
  '{{THRESHOLD}}', string(cat.threshold))]
var categoriesXml = join(categoryEntries, '\n')

var contentSafetyXml = contentSafetyEnabled
  ? replace(
      replace(snippetContentSafety, '{{SHIELD_PROMPT}}', shieldPrompt ? 'true' : 'false'),
      '{{CATEGORIES}}', categoriesXml)
  : ''

// --- PII: Custom Regex Patterns ---
var regexEntries = [for p in piiRegexPatterns: replace(
  replace(snippetPiiRegexEntry, '{{PATTERN}}', p.pattern),
  '{{CATEGORY}}', p.category)]
var regexEntriesXml = !empty(piiRegexPatterns) ? join(regexEntries, ',\n') : ''

// --- PII: Anonymization Inbound ---
var piiAnonymizeInboundXml = piiEnabled && piiMode == 'anonymize'
  ? replace(
      replace(
        replace(
          replace(snippetPiiAnonymizationInbound, '{{PII_CONFIDENCE}}', piiConfidence),
          '{{PII_EXCLUSIONS}}', piiExclusions),
        '{{PII_LANGUAGE}}', piiLanguage),
      '{{REGEX_ENTRIES}}', regexEntriesXml)
  : ''

// --- PII: Blocking Inbound ---
var piiBlockInboundXml = piiEnabled && piiMode == 'block'
  ? replace(
      replace(
        replace(
          replace(snippetPiiBlockingInbound, '{{PII_CONFIDENCE}}', piiConfidence),
          '{{PII_EXCLUSIONS}}', piiExclusions),
        '{{PII_LANGUAGE}}', piiLanguage),
      '{{REGEX_ENTRIES}}', regexEntriesXml)
  : ''

var piiInboundXml = piiEnabled
  ? (piiMode == 'anonymize' ? piiAnonymizeInboundXml : piiBlockInboundXml)
  : ''

// --- Usage Tracking ---
var usageTrackingXml = usageEnabled
  ? replace(
      replace(
        replace(
          replace(
            replace(snippetUsageTracking, '{{APP_ID_HEADER}}', appIdHeader),
            '{{CD1_HEADER}}', cd1Header),
          '{{CD1_DEFAULT}}', cd1Default),
        '{{CD2_HEADER}}', cd2Header),
      '{{CD2_DEFAULT}}', cd2Default)
  : ''

// ============================================================================
// BUILD OUTBOUND POLICY SECTIONS
// ============================================================================

var piiStateSavingXml = piiEnabled && piiMode == 'anonymize' && piiStateSavingEnabled
  ? snippetPiiStateSaving
  : ''

var piiDeanonymizeOutboundXml = piiEnabled && piiMode == 'anonymize'
  ? replace(snippetPiiDeanonymizationOutbound, '{{PII_STATE_SAVING}}', piiStateSavingXml)
  : ''

// ============================================================================
// BUILD ON-ERROR POLICY SECTIONS
// ============================================================================

var alertsOnErrorXml = alertsEnabled && throttlingEvents
  ? snippetAlertsThrottling
  : ''

// ============================================================================
// ASSEMBLE FINAL POLICY XML
// ============================================================================

// Conditionally build section arrays (only include non-empty sections)
var inboundSections = flatten([
  jwtAuthEnabled ? [snippetJwtAuth] : []
  needsModelExtraction ? [modelExtractionXml] : []
  modelAccessEnabled ? [modelAccessXml] : []
  capacityEnabled ? [capacityXml] : []
  contentSafetyEnabled ? [contentSafetyXml] : []
  piiEnabled ? [piiInboundXml] : []
  usageEnabled ? [usageTrackingXml] : []
])

var outboundSections = flatten([
  (piiEnabled && piiMode == 'anonymize') ? [piiDeanonymizeOutboundXml] : []
])

var onErrorSections = flatten([
  (alertsEnabled && throttlingEvents) ? [alertsOnErrorXml] : []
])

// Join sections with newlines and assemble into master template
var inboundPoliciesXml = join(inboundSections, '\n')
var outboundPoliciesXml = join(outboundSections, '\n')
var onErrorPoliciesXml = join(onErrorSections, '\n')

var policyXml = replace(
  replace(
    replace(masterTemplate, '{{INBOUND_POLICIES}}', inboundPoliciesXml),
    '{{OUTBOUND_POLICIES}}', outboundPoliciesXml),
  '{{ON_ERROR_POLICIES}}', onErrorPoliciesXml)

// ============================================================================
// BUILD SERVICES ARRAY WITH GENERATED POLICY
// ============================================================================

var servicesWithPolicy = [for svc in servicesList: {
  code: svc.code
  endpointSecretName: svc.endpointSecretName
  apiKeySecretName: svc.apiKeySecretName
  policyXml: policyXml
}]

// ============================================================================
// DEPLOY ACCESS CONTRACT USING EXISTING MAIN MODULE
// ============================================================================

module accessContract '../main.bicep' = {
  name: 'contract-${contractInfo.businessUnit}-${contractInfo.useCaseName}-${contractInfo.environment}'
  params: {
    apim: apimConfig
    keyVault: kvConfig
    useTargetAzureKeyVault: kvEnabled
    useCase: {
      businessUnit: contractInfo.businessUnit
      useCaseName: contractInfo.useCaseName
      environment: contractInfo.environment
    }
    apiNameMapping: contractRequest.apiNameMapping
    services: servicesWithPolicy
    productTerms: contractInfo.?productTerms ?? ''
    useTargetFoundry: foundryEnabled
    foundry: foundryCoords
    foundryConfig: foundryConfigFinal
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output apimGatewayUrl string = accessContract.outputs.apimGatewayUrl
output useKeyVault bool = accessContract.outputs.useKeyVault
output products array = accessContract.outputs.products
output subscriptions array = accessContract.outputs.subscriptions

#disable-next-line outputs-should-not-contain-secrets
output endpoints array = accessContract.outputs.endpoints

output useFoundry bool = accessContract.outputs.useFoundry
output foundryConnections array = accessContract.outputs.foundryConnections

@description('The generated APIM policy XML for inspection/debugging')
output generatedPolicyXml string = policyXml
