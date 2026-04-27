using '../../../main.bicep'

// ============================================================================
// HR PII Analytics - LLM reasoning over PII processing telemetry (no PII fragments) - Generated from PII Testing Notebook
// ============================================================================

param apim = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'
  resourceGroupName: 'placeholder'
  name: 'placeholder'
}

param keyVault = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'
  resourceGroupName: 'placeholder'
  name: 'placeholder'
}

param useTargetAzureKeyVault = false

param useCase = {
  businessUnit: 'HR'
  useCaseName:  'PIIAnalytics'
  environment:  'DEV'
}

param apiNameMapping = {
  LLM: ['universal-llm-api', 'azure-openai-api', 'unified-ai-api']
}

param services = [
  {
    code: 'LLM'
    endpointSecretName: 'HR-PII-LLM-ENDPOINT'
    apiKeySecretName:   'HR-PII-LLM-KEY'
    policyXml: loadTextContent('ai-product-policy.xml')
  }
]

param productTerms = 'PII Analytics Access Contract - HR PII Analytics - LLM reasoning over PII processing telemetry (no PII fragments)'

param useTargetFoundry = false

param foundry = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'
  resourceGroupName: 'placeholder'
  accountName: 'placeholder'
  projectName: 'placeholder'
}
