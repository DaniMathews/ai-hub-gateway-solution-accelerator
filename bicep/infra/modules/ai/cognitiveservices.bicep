param name string
param location string = resourceGroup().location
param tags object = {}
param managedIdentityName string = ''
param deployments array = []
param kind string = 'OpenAI'
param sku object = {
  name: 'S0'
}
param deploymentCapacity int = 1

// Networking
param publicNetworkAccess string = 'Disabled'
param aiPrivateEndpointName string
param vNetName string
param vNetLocation string
param privateEndpointSubnetName string
param apimSubnetName string = ''
param functionAppSubnetName string = ''
param openAiDnsZoneName string

// Use existing network/dns zone - Legacy parameters (used when dnsZoneResourceId is not provided)
param dnsZoneRG string = ''
param dnsSubscriptionId string = ''
param vNetRG string

// New parameter: Direct DNS zone resource ID (preferred over dnsZoneRG/dnsSubscriptionId)
param dnsZoneResourceId string = ''
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vNetName
  scope: resourceGroup(vNetRG)
}

// Get existing subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = if (!empty(apimSubnetName)) {
  name: apimSubnetName
  parent: vnet
}

resource functionAppSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = if (!empty(functionAppSubnetName)) {
  name: functionAppSubnetName
  parent: vnet
}

// Build virtualNetworkRules for the 3 accelerator subnets (skip any whose name was not provided)
var virtualNetworkRules = union(
  [
    {
      id: subnet.id
      ignoreMissingVnetServiceEndpoint: false
    }
  ],
  !empty(apimSubnetName) ? [
    {
      id: apimSubnet.id
      ignoreMissingVnetServiceEndpoint: false
    }
  ] : [],
  !empty(functionAppSubnetName) ? [
    {
      id: functionAppSubnet.id
      ignoreMissingVnetServiceEndpoint: false
    }
  ] : []
)

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

resource account 'Microsoft.CognitiveServices/accounts@2026-01-15-preview' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  kind: kind
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: toLower(name)
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: virtualNetworkRules
    }
  }
  sku: sku
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview' = [for deployment in deployments: {
  parent: account
  name: deployment.name
  properties: {
    model: deployment.model
    raiPolicyName: contains(deployment, 'raiPolicyName') ? deployment.raiPolicyName : null
  }
  sku: contains(deployment, 'sku') ? deployment.sku : {
    name: 'Standard'
    capacity: deploymentCapacity
  }
}]

module privateEndpoint '../networking/private-endpoint.bicep' = {
  name: '${account.name}-pe'
  params: {
    groupIds: [
      'account'
    ]
    dnsZoneName: openAiDnsZoneName
    name: aiPrivateEndpointName
    privateLinkServiceId: account.id
    location: vNetLocation
    privateEndpointSubnetId: subnet.id
    dnsZoneRG: dnsZoneRG
    dnsSubId: dnsSubscriptionId
    dnsZoneResourceId: dnsZoneResourceId
    tags: tags
  }
  dependsOn: [
    deployment
  ]
}

output openAiName string = account.name
output openAiEndpointUri string = '${account.properties.endpoint}openai/'

output aiServiceName string = account.name
output aiServiceEndpoint string = account.properties.endpoint
