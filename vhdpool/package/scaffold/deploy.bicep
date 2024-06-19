@allowed([
  '-mariner'
  ''
])
param resourceNameSuffix string = ''
@allowed([
  'eastus'
])
param location string

var agentIdentityName = 'nodesig-agent-identity${resourceNameSuffix}'
var publicIpName = 'nodesig-pip${resourceNameSuffix}'
var natGatewayName = 'nodesig-nat-gw${resourceNameSuffix}'
var nsgName = 'nodesig-agent-nsg${resourceNameSuffix}'
var vnetName = 'nodesig-pool-vnet${resourceNameSuffix}'

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: agentIdentityName
  location: location
}

resource publicip 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource natGateway 'Microsoft.Network/natGateways@2021-05-01' = {
  name: natGatewayName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: publicip.id
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-vnet-ssh'
        properties: {
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          priority: 110
        }
      }
      {
        name: 'allow-internet-outbound'
        properties: {
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
          priority: 111
        }
      }
      {
        name: 'deny-all-other-inbound-traffic'
        properties: {
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          priority: 112
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['172.16.0.0/12']
    }
    subnets: [
      {
        name: 'packer'
        properties: {
          // don't use 172.17.0.0/16! - this conflicts with the default docker bridge network CIDR configured on 1es agents
          addressPrefix: '172.18.0.0/16'
          natGateway: {
            id: natGateway.id
          }
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}
