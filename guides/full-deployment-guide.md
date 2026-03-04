# 🏗️ Full Deployment Guide - All Environments

This comprehensive guide covers deploying AI Citadel Governance Hub across **development, staging, and production** environments with enterprise-grade configuration, networking, and governance.

For quick non-production deployments, see the [Quick Deployment Guide](./quick-deployment-guide.md).

---

## 📋 Table of Contents

1. [Prerequisites](#-prerequisites)
2. [Deployment Preparation](#-deployment-preparation)
   - [Parameter Files Strategy](#1-parameter-files-strategy)
   - [Resource Naming & Tagging](#2-resource-naming--tagging)
   - [Network Architecture](#3-network-architecture)
   - [AI Model Deployment](#4-ai-model-deployment-optional)
   - [Log Analytics Strategy](#5-log-analytics-strategy)
   - [Inference API Diagnostic Logging](#6-inference-api-diagnostic-logging)
   - [Security & Compliance](#7-security--compliance)
3. [Source Control Strategy](#-source-control-strategy)
4. [Deployment Execution](#-deployment-execution)
5. [Environment-Specific Configurations](#-environment-specific-configurations)
6. [Post-Deployment Validation](#-post-deployment-validation)
7. [Troubleshooting](#-troubleshooting)

---

## ✅ Prerequisites

### Azure Requirements

| Requirement | Details |
|-------------|---------|
| **Azure Subscription** | Active subscription with sufficient quota |
| **Permissions** | Owner or Contributor + User Access Administrator |
| **Resource Providers** | All required providers registered (see below) |
| **Service Quotas** | Verified quotas for LLMs, CosmosDB and other elements |

## Deployment Decisions Checklist

Use the below checklist to plan your deployment configuration:

- [ ] Subscription allocation
  - [ ] New subscription
  - [ ] Existing subscription
- [ ] Target Azure Region(s)
  - [ ] Primary Region (for core governance components)
  - [ ] Regions for Foundry instances and model deployments
- [ ] Network Approach
  - [ ] Hub-Based (using new subnets in existing hub network)
  - [ ] AIGovSpoke-Hub-Spoke (create dedicated spoke VNet linked to hub)
- [ ] Bring-Your-Own Network
  - [ ] Create new VNet with customized address space
  - [ ] Use existing VNet integration (vnet/subnets already created & configured)
  - [ ] Use exiting Private DNS Zones (better with using existing VNet)
  - [ ] Create new Private DNS Zones (better with new VNet)
- [ ] APIM Network Configuration
  - [ ] External (public endpoint, suitable for dev/test)
  - [ ] Internal (private endpoint, recommended for production)
  - [ ] APIM Custom Domains (list them for gateway, developer portal and management names)
- [ ] Log Analytics Strategy
  - [ ] New Workspace will be created
  - [ ] Use existing centralized Workspace (cross-environment)
- [ ] Resource Naming Convention & tags
  - [ ] Auto-generated names
  - [ ] Custom names/tags per organizational standards
- [ ] Microsoft Foundry Model Deployment
  - [ ] Deploy models as part of AI Citadel deployment (specify models/regions)
  - [ ] None (use existing deployments that will be onboarded later)
- [ ] Services SKUs & Capacities per Environment
  - [ ] Development (cost-optimized SKUs)
  - [ ] Staging (production SKUs with reduced capacity)
  - [ ] Production (production SKUs with full capacity)
- [ ] Inference API Diagnostic Logging
  - [ ] Azure Monitor LLM log verbosity (enabled/disabled, message capture, max payload size)
  - [ ] Application Insights log headers and body capture size
  - [ ] Use defaults (recommended) or customize per environment
- [ ] Source Control Strategy
  - [ ] Single repository with branches per environment
      - [ ] Branch for original unchanged Citadel Governance Hub repo (synchronized with upstream)
      - [ ] Branches for dev, staging, production with environment-specific parameter files (apply changes through new parameter files only)
  - [ ] Separate repositories per environment (with similar branching strategy to point 1)
  - [ ] Automation Strategy
      - [ ] Manual deployments using `azd up` or `az deployment sub create`
      - [ ] CI/CD pipelines (i.e. Azure DevOps or GitHub Actions) for automated deployments

Leverage deployment parameter files ([main.bicepparam](../bicep/infra/main.bicepparam)) to capture these decisions for each environment.

### Required Resource Providers

You can use Azure Cloud Shell or your local Azure CLI installation to register the required resource providers.

First we make sure that the target subscription is selected:

```bash 
az login
az account list --output table
az account set --subscription "<subscription-name or id>"
az account show --output table
```

Then register all required resource providers:

```bash
# Register all required providers
az provider register --namespace Microsoft.AlertsManagement
az provider register --namespace Microsoft.ApiCenter
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Automation
az provider register --namespace Microsoft.Cache
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Diagnostics
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.EventHub
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.MachineLearningServices
az provider register --namespace Microsoft.ManagedIdentity
az provider register --namespace Microsoft.Monitor
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Resources
az provider register --namespace Microsoft.Search
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Web

# Verify registration status
az provider list --query "[?registrationState=='Registered'].namespace" -o table
```

### Deployment Tools

**Option 1: Local Machine**
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.50.0+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (v0.20.0+)
- [Git](https://git-scm.com/downloads)
- [VS Code](https://code.visualstudio.com/) with extensions:
  - Bicep

**Option 2: Azure Cloud Shell**
- All tools pre-installed
- Storage account for persistence must be attached
- Built-in editor (in the classic mode)

**Option 3:  DevOps (i.e. Azure DevOps / GitHub Actions)**
- Self-hosted or Microsoft-hosted agents
- Service Principal with appropriate permissions
- Secure variable groups for secrets

---

## 🎯 Deployment Preparation

Based on your choices in the [Deployment Decisions Checklist](#deployment-decisions-checklist), you can now prepare your deployment configuration.

For source control, make sure you have a working directory linked to your source control repository.

First you need to get the deployment template files:

```bash
# Create a working directory:
mkdir ai-hub-citadel-deployment
# Make the repository your current directory:
cd ai-hub-citadel-deployment # it may differ if you used git clone

# Copy repo files
azd init --template Azure-Samples/ai-hub-gateway-solution-accelerator -e ai-hub-citadel-dev --branch citadel-v1

# or use git clone:
# git clone https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator.git
# git checkout citadel-v1

```

Once you have the Infrastructure-as-Code files, proceed to configure your deployment based on the following strategies.

You can perform the deployment using either `azd up` (recommended) or `az deployment sub create` commands.

### 1. Parameter Files Strategy

AI Citadel Governance Hub uses **Bicep parameter files (.bicepparam)** for environment-specific configurations.

>NOTE: Always keep a separate copy of your customized parameter files with different names of the main repository `main.bicepparam` to avoid overwriting during updates.

#### Available Parameter Files

| File | Purpose | Use Case |
|------|---------|----------|
| [`main.bicepparam`](../bicep/infra/main.bicepparam) | Environment variables | Used in azd deployments, CI/CD (Default values come from here) |
| [`main.parameters.dev.bicepparam`](../bicep/infra/main.parameters.dev.bicepparam) | Development | Dev/test environments |
| [`main.parameters.prod.bicepparam`](../bicep/infra/main.parameters.prod.bicepparam) | Production | Production workloads |
| [`main.parameters.complete.bicepparam`](../bicep/infra/main.parameters.complete.bicepparam) | Reference | All parameters documented |

#### Parameter File Structure

```bicep
using './main.bicep'

// Basic Configuration
param environmentName = 'citadel-dev'
param location = 'eastus'
param tags = {
  'azd-env-name': 'citadel-dev'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Compute SKUs
param apimSku = 'Developer'
param apimSkuUnits = 1

// Networking
param useExistingVnet = false
param useExistingLogAnalytics = false

// Features
param enableAIFoundry = true
param enableAPICenter = true
```

---

### 2. Resource Naming & Tagging

#### Naming Strategy

AI Citadel supports two naming approaches:

**Option A: Auto-Generated Names (for default non-production deployment)**
```bicep
param resourceGroupName = ''  // Auto-generated: rg-citadel-dev
param apimServiceName = ''    // Auto-generated: apim-abc123def
param logAnalyticsName = ''   // Auto-generated: log-abc123def
```

Benefits:
- ✅ Quick naming across environments
- ✅ Unique names prevent conflicts
- ✅ Includes environment hash for traceability

**Option B: Custom Names**
```bicep
param resourceGroupName = 'rg-ai-gov-citadel-prod-eastus'
param apimServiceName = 'apim-ai-gov-citadel-prod'
param logAnalyticsName = 'law-ai-gov-citadel-shared'
```

Benefits:
- ✅ Human-readable names
- ✅ Matches organizational naming standards
- ✅ Easier to locate in portal

#### Tagging Strategy

**Minimum Required Tags:**
```bicep
param tags = {
  'azd-env-name': 'ai-gov-citadel-prod'
  Environment: 'Production'
  CostCenter: 'Platform'
  Owner: 'platform-team@company.com'
  Criticality: 'High'
}
```

**Recommended Tags by Environment:**

| Tag | Dev | Staging | Production |
|-----|-----|---------|------------|
| Environment | Development | Staging | Production |
| Criticality | Low | Medium | High |
| CostCenter | Engineering | Engineering | Platform |

---

### 3. Network Architecture

#### Network Deployment Approaches

AI Citadel Governance Hub supports **two architectural patterns** for network integration.

Based on your decisions in the earlier checklist, choose one of the following approaches:

##### **Approach 1: Hub-Based (Citadel as Part of Hub)**

Citadel Governance Hub deployed **within** your existing hub VNet.

```
┌─────────────────────────────────────┐
│         Hub Network (VNet)          │
│  ┌──────────────────────────────┐   │
│  │   Citadel Governance Hub     │   │
│  │   - APIM (External/Internal) │   │
│  │   - Private Endpoints        │   │
│  │   - Log Analytics            │   │
│  └──────────────────────────────┘   │
│  ┌──────────────────────────────┐   │
│  │   Shared Services            │   │
│  │   - Azure Firewall           │   │
│  │   - DNS                      │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
           │           │
           ▼           ▼
    ┌──────────┐  ┌──────────┐
    │ Spoke 1  │  │ Spoke 2  │
    │ Agents   │  │ Agents   │
    └──────────┘  └──────────┘
```

**Configuration:**
```bicep
param useExistingVnet = true
param vnetName = 'vnet-hub-eastus'
param existingVnetRG = 'rg-network-hub'
param apimSubnetName = 'snet-citadel-apim'
param privateEndpointSubnetName = 'snet-citadel-private-endpoints'
param functionAppSubnetName = 'snet-citadel-functions'
```

**When to Use:**
- ✅ Citadel manages all enterprise AI traffic
- ✅ Direct spoke-to-hub connectivity
- ✅ Simplified network topology

---

##### **Approach 2: Hub-Spoke-Hub (Citadel as Dedicated Spoke)**

Citadel deployed in a **dedicated spoke** with firewall in between.

```
                 ┌─────────────┐
                 │ Hub Network │
                 │  - Firewall │
                 │  - DNS      │
                 └──────┬──────┘
                        │
         ┌──────────────┼──────────────┐
         ▼              ▼              ▼
  ┌────────────┐ ┌────────────┐ ┌────────────┐
  │  Spoke 1   │ │  Citadel   │ │  Spoke 2   │
  │  Agents    │ │  Governance│ │  Agents    │
  └────────────┘ │   Hub      │ └────────────┘
                 │  - APIM    │
                 │  - PE      │
                 └────────────┘
```

**Configuration:**
```bicep
param useExistingVnet = false  // Creates new spoke VNet
param vnetName = 'vnet-citadel-eastus'
param vnetAddressPrefix = '10.170.0.0/24'
param dnsZoneRG = 'rg-network-hub'
param dnsSubscriptionId = '<hub-subscription-id>'

// Post-deployment: Configure VNet peering to hub
```

**When to Use:**
- ✅ Defense-in-depth security (dual inspection)
- ✅ Isolated AI workloads from general traffic
- ✅ Separate cost centers/subscriptions
- ✅ Compliance requirements for network isolation

---

#### Network Setup Options

##### **Option 1: Create New Network (Greenfield)**

Citadel creates all networking components:

```bicep
param useExistingVnet = false
param vnetAddressPrefix = '10.170.0.0/24'
param apimSubnetPrefix = '10.170.0.0/26'
param privateEndpointSubnetPrefix = '10.170.0.64/26'
param functionAppSubnetPrefix = '10.170.0.128/26'

// Network access
param apimNetworkType = 'External'  // or 'Internal' for production
param apimV2UsePrivateEndpoint = true
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Enabled'  // Required during deployment of APIM v2 SKUs
```

**Includes:**
- ✅ Virtual Network with subnets
- ✅ Network Security Groups
- ✅ Private DNS Zones
- ✅ Private Endpoints for all services
- ✅ Route tables (needed for APIM Developer and Premium SKUs)

---

##### **Option 2: Bring Your Own Network (Brownfield)**

Integrate with existing enterprise network:

```bicep
param useExistingVnet = true
param vnetName = 'vnet-hub-prod-eastus'
param existingVnetRG = 'rg-network-prod'

// Subnet names (must exist)
param apimSubnetName = 'snet-citadel-apim'
param privateEndpointSubnetName = 'snet-citadel-pe'
param functionAppSubnetName = 'snet-citadel-functions'

// DNS configuration
param dnsZoneRG = 'rg-network-dns'
param dnsSubscriptionId = '00000000-0000-0000-0000-000000000000'
```

**Prerequisites:**
1. VNet with sufficient address space
2. Three subnets created:
   - APIM subnet: `/26` or larger (64 IPs)
   - Private endpoint subnet: `/26` or larger
   - Function App subnet: `/26` or larger
3. Private DNS zones created (or delegated)
4. NSG required rules configured for APIM subnet

**Required DNS Zones:**
- `privatelink.vaultcore.azure.com`
- `privatelink.cognitiveservices.azure.com`
- `privatelink.vaultcore.azure.net`
- `privatelink.monitor.azure.com`
- `privatelink.servicebus.windows.net`
- `privatelink.documents.azure.com`
- `privatelink.blob.core.windows.net`
- `privatelink.file.core.windows.net`
- `privatelink.table.core.windows.net`
- `privatelink.queue.core.windows.net`
- `privatelink.azure-api.net` (for APIM v2 SKUs)
- `privatelink.services.ai.azure.com` (for AI Foundry)

**APIM Subnet Requirements:**

For **Developer/Premium SKU** (VNet injection):
```bash
# No special delegation required
# NSG must allow all required APIM management traffic
# must have required service endpoints enabled
# associated with APIM route table
```

For **StandardV2/PremiumV2 SKU** (Private Endpoint):
```bash
# Standard subnet configuration
# Private endpoint will be created
```

Detailed guide: [Bring Your Own Network](./network-approach.md)

---

### 4. AI Model Deployment (Optional)

#### Microsoft Foundry Configuration

AI Citadel can deploy **Microsoft Foundry instances** with model deployments as part of the primary landing zone provisioning.

Input parameters are separated into two parts:

##### Foundry instances deployment

```bicep
// AI Foundry instances configuration array
param aiFoundryInstances = [
  {
    name: readEnvironmentVariable('AI_FOUNDRY_RESOURCE_NAME', '')
    location: readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
  {
    name: readEnvironmentVariable('AI_FOUNDRY_RESOURCE_NAME', '')
    location: 'eastus2'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
]
```

The above, creates two Foundry instances in `swedencentral` and `eastus2` regions as examples.

This allows you to deploy models in multiple regions for geo-redundancy, added capacity or accessing restricted regional models.

###### Foundry model deployments

```bicep
// AI Foundry model deployments configuration
param aiFoundryModelsConfig = [
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0 // First instance in aiFoundryInstances array
  }
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 0
  }
  {
    name: 'Phi-4'
    publisher: 'Microsoft'
    version: '3'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 0
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
  {
    name: 'gpt-5'
    publisher: 'OpenAI'
    version: '2025-08-07'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 1 // Second instance in aiFoundryInstances array
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 1
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 1
  }
]
```

>NOTE: Ensure that your target subscription has sufficient quota for the selected models.

##### Disable Microsoft Foundry Model deployment

If you are planning to leverage existing model deployments or you are planning to provision the LLMs separately, you can skip model deployment during Citadel provisioning. 

```bicep
param aiFoundryModelsConfig = [] // No models will be deployed as part of AI Citadel primary deployment
```

---

### 5. Log Analytics Strategy

#### Option 1: Create New Log Analytics Workspace

**Recommended for:** Isolated environments, proof-of-concept, dedicated subscriptions

```bicep
param useExistingLogAnalytics = false
param logAnalyticsName = ''  // Auto-generated if empty or supply a compliant name.
```

**Benefits:**
- ✅ Isolated logs per environment
- ✅ Independent retention policies
- ✅ Simplified RBAC
- ✅ Environment-specific dashboards

**Typical Setup:**
```
┌────────────────┐  ┌────────────────┐  ┌─────────────────┐
│ LAW Dev        │  │ LAW Staging    │  │ LAW Prod        │
│ - 30d retention│  │ - 90d retention│  │ - 180d retention│
│ - Dev RBAC     │  │ - Ops RBAC     │  │ - Audit RBAC    │
└────────────────┘  └────────────────┘  └─────────────────┘
```

---

#### Option 2: Bring Your Own Log Analytics (Recommended for Enterprise)

**Recommended for:** Enterprise, multi-environment, centralized monitoring

```bicep
param useExistingLogAnalytics = true
param existingLogAnalyticsName = 'law-centralized-prod'
param existingLogAnalyticsRG = 'rg-monitoring-prod'
param existingLogAnalyticsSubscriptionId = '00000000-0000-0000-0000-000000000000'
```

>NOTE: Log Analytics can exists in a different subscription than the Citadel governance hub deployment subscription.

**Benefits:**
- ✅ Centralized logging across all environments
- ✅ Integration with central SIEM
- ✅ Cross-environment correlation
- ✅ Compliance and audit requirements

**Typical Setup:**
```
              ┌──────────────────────────┐
              │ Centralized LAW (Prod)   │
              │ - All environments       │
              │ - 180d retention         │
              │ - Advanced analytics     │
              └──────────────────────────┘
                            ▲
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
    ┌────────┐         ┌────────┐        ┌────────┐
    │  Dev   │         │Staging │        │  Prod  │
    │ Citadel│         │Citadel │        │ Citadel│
    └────────┘         └────────┘        └────────┘
```

---

### 6. Inference API Diagnostic Logging

AI Citadel configures **per-API diagnostic logging** on every inference API (Universal LLM API and Azure OpenAI API). Two diagnostic channels are provisioned:

| Channel | Purpose | Default Destination |
|---------|---------|--------------------|
| **Azure Monitor** (`azuremonitor`) | LLM-aware diagnostics sent to Log Analytics | Azure Monitor / Log Analytics |
| **Application Insights** (`applicationinsights`) | Request/response tracing with custom headers | Application Insights |

Both channels are fully configurable through the deployment parameter files.

#### Azure Monitor Log Settings (`azureMonitorLogSettings`)

Controls frontend/backend request and response header capture, body byte limits, and **LLM-specific** log settings (prompt/completion logging).

**Default values:**

```bicep
param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }   // No frontend headers/body captured by default
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }   // No backend headers/body captured by default
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'                                  // LLM logging enabled
    requests:  { messages: 'all', maxSizeInBytes: 262144 }  // Capture all prompt messages (up to 256 KB)
    responses: { messages: 'all', maxSizeInBytes: 262144 }  // Capture all completion messages (up to 256 KB)
  }
}
```

| Property | Default | Description |
|----------|---------|-------------|
| `frontend.request.headers` | `[]` | HTTP headers to capture from the client request |
| `frontend.request.body.bytes` | `0` | Max bytes of client request body to log (`0` = none) |
| `frontend.response.headers` | `[]` | HTTP headers to capture from the response to client |
| `frontend.response.body.bytes` | `0` | Max bytes of response body to log (`0` = none) |
| `backend.request.headers` | `[]` | HTTP headers to capture from the backend request |
| `backend.request.body.bytes` | `0` | Max bytes of backend request body to log (`0` = none) |
| `backend.response.headers` | `[]` | HTTP headers to capture from backend response |
| `backend.response.body.bytes` | `0` | Max bytes of backend response body to log (`0` = none) |
| `largeLanguageModel.logs` | `'enabled'` | Enable or disable LLM-specific logging (`'enabled'` / `'disabled'`) |
| `largeLanguageModel.requests.messages` | `'all'` | Which prompt messages to capture (`'all'` / `'none'`) |
| `largeLanguageModel.requests.maxSizeInBytes` | `262144` | Maximum prompt payload size in bytes (256 KB) |
| `largeLanguageModel.responses.messages` | `'all'` | Which completion messages to capture (`'all'` / `'none'`) |
| `largeLanguageModel.responses.maxSizeInBytes` | `262144` | Maximum completion payload size in bytes (256 KB) |

**Example — Production with header capture and reduced LLM payload:**
```bicep
param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [ 'Content-type', 'User-agent' ], body: { bytes: 0 } }
    response: { headers: [ 'x-ms-region' ], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [ 'Content-type' ], body: { bytes: 8192 } }
    response: { headers: [ 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ], body: { bytes: 8192 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests:  { messages: 'all', maxSizeInBytes: 131072 }  // 128 KB limit
    responses: { messages: 'all', maxSizeInBytes: 131072 }
  }
}
```

**Example — Disable LLM prompt/completion logging (privacy-sensitive environments):**
```bicep
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
    logs: 'disabled'
    requests:  { messages: 'none', maxSizeInBytes: 0 }
    responses: { messages: 'none', maxSizeInBytes: 0 }
  }
}
```

---

#### Application Insights Log Settings (`appInsightsLogSettings`)

Controls which HTTP headers are captured and how many bytes of request/response body are logged to Application Insights for all inference APIs.

**Default values:**

```bicep
param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }  // No body captured by default
}
```

| Property | Default | Description |
|----------|---------|-------------|
| `headers` | `[ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]` | HTTP headers captured in both frontend and backend request/response traces |
| `body.bytes` | `0` | Max bytes of request/response body to log (`0` = none) |

**Example — Capture up to 8 KB of body content:**
```bicep
param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 8192 }
}
```

**Example — Minimal header capture for cost-sensitive environments:**
```bicep
param appInsightsLogSettings = {
  headers: [ 'Content-type' ]
  body: { bytes: 0 }
}
```

---

#### Recommended Settings by Environment

| Setting | Development | Staging | Production |
|---------|-------------|---------|------------|
| **Azure Monitor LLM logs** | `'enabled'` | `'enabled'` | `'enabled'` (or `'disabled'` for PII-sensitive workloads) |
| **LLM messages capture** | `'all'` | `'all'` | `'all'` or `'none'` |
| **LLM max payload (bytes)** | `262144` (256 KB) | `262144` (256 KB) | `131072`–`262144` (128–256 KB) |
| **App Insights body bytes** | `8192` (8 KB) | `0` | `0` |
| **App Insights headers** | All 5 defaults | All 5 defaults | All 5 defaults |

> **Note:** Increasing body byte capture or LLM payload sizes will increase Log Analytics and Application Insights ingestion costs. For production environments, balance observability needs against cost and data-sensitivity requirements.

---

### 7. Security & Compliance

#### Entra ID Authentication

**Production Requirement:** Enable JWT-based authentication

```bicep
param entraAuth = true
param entraTenantId = '00000000-0000-0000-0000-000000000000'
param entraClientId = '11111111-2222-3333-4444-555555555555'
param entraAudience = 'api://citadel-gateway'
```

**Setup Steps:**
1. Register App in Entra ID
2. Configure API permissions
3. Create client secret (store in Key Vault)
4. Update parameter file

Guide: [Entra ID Authentication](.)

#### Network Security

All applicable network security settings are configurable through the parameters of the accelerator:

**Suggested Production Configuration:**
```bicep
// APIM Security
param apimNetworkType = 'Internal'  // No public access (applies to APIM Developer and Premium SKUs)
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = false

// Service Network Access
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Disabled'  // Enable during deployment, disable after for APIM Standardv2 and PremiumV2 SKUs
param languageServiceExternalNetworkAccess = 'Disabled'
param aiContentSafetyExternalNetworkAccess = 'Disabled'

...

```

---

## 🚀 Deployment Execution

It is recommended to leverage Azure Developer CLI (`azd`) for simplified deployments of both the infrastructure and application (Logic Apps workflows).

Based on the configured parameter files, you can deploy using either `az deployment sub create` or `azd up`.

### Using `az deployment sub create`:

**For Development:**
```bash
az deployment sub create \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.dev.bicepparam
```

**For Production:**
```bash
az deployment sub create \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.prod.bicepparam
```

**For Custom Environments:**
1. Copy `main.parameters.complete.bicepparam`
2. Rename to `main.parameters.<env>.bicepparam`
3. Customize values
4. Version control the file

>Note: Using `az deployment sub create` will only provision the infrastructure. You still will need to deploy the `Logic App` workflows separately after the infrastructure is ready.

### Using `azd up`:

This automatically picks up the `main.bicepparam` file. You can override specific parameters using environment variables or by modifying the `main.bicepparam` file directly.

```bash
# Authenticate to Azure
# append --tenant-id <your-tenant-id> if needed
azd auth login

# Initialize environment
azd env new ai-hub-citadel-dev-01

# Provision and deploy everything based on defaults
azd up
```

>NOTE: Using `azd up` will use the `main.bicepparam` file for parameter values. You can modify it or set environment variables to override specific parameters. This command provisions the infrastructure and deploys the Logic App workflows in one step.

---

## ✅ Post-Deployment Validation

### Verify Resource Deployment

```bash
# List all resources in resource group
RG_NAME=$(az deployment sub show \
  --name <deployment-name> \
  --query properties.outputs.resourceGroupName.value -o tsv)

az resource list \
  --resource-group $RG_NAME \
  --output table

```

### Validate Governance Hub functionality

This repo includes set of validation NoteBooks under `/validation` folder.

- [citadel-governance-hub-primary-tests.ipynb](../validation/citadel-governance-hub-primary-tests.ipynb): Initial discovery of the deployed governance hub and help in creating the first access contract.
- [llm-backend-onboarding-runner.ipynb](../validation/llm-backend-onboarding-runner.ipynb): Onboard existing LLM backends & configure its routing to the governance hub and validate connectivity.

---

## Deploy Citadel Governance Hub updates

Once the initial deployment is completed, you can still further updates and enhancements of the governance hub by synchronizing your local repository `original branch` with the upstream changes, then you can create a `Pull-Request` to your environment-specific branch to merge the changes.

## 🚨 Troubleshooting

Visit the [Deployment Troubleshooting Guide](./#) for common issues and resolutions.

---

### Getting Help

- **GitHub Issues:** [Report a bug](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/issues)

---

## 📚 Next Steps

**After Successful Deployment:**

- **Enable Security**
   - [Entra ID Authentication](./entraid-auth-validation.md)
   - [PII Detection](./pii-masking-apim.md)

- **Set Up Monitoring**
   - [Power BI Dashboard](./power-bi-dashboard.md)
   - [Alert Configuration](./throttling-events-handling.md)

- **Onboard Teams**
  - [Citadel Access Contracts](./citadel-access-contracts.md)

- **Deploy LLM Backends**
   - [Onboard Existing LLMs](./LLM-Backend-Onboarding-Guide.md)
   - [LLM Routing Architecture](./llm-routing-architecture.md)

---

**Congratulations! Your AI Citadel Governance Hub is now deployed and ready for enterprise AI workloads.** 🎉
