targetScope = 'subscription'
@allowed([
  '-mariner'
  ''
])
param resourceNameSuffix string = ''
@allowed([
  'test'
  'prod'
])
param env string

// 1ES Service Principal
var oneESId = env == 'prod' ? '5a152836-f9e8-4817-992a-5e09dfa87aab' : '1a59497d-7230-45aa-802e-d57bf83e48f4' 

var agentIdentityName = 'nodesig-agent-identity${resourceNameSuffix}'
var resourceGroupName = 'nodesig${env}-agent-pool${resourceNameSuffix}'

resource contributorRoleDef 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  scope: subscription()
}

// needed for generating user-delegation SAS tokens for storage containers holding VHD blobs
resource storageBlobDataContributorRoleDef 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

resource managedIdentityOpRoleDef 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: 'f1a07417-d97a-45cb-824c-7a7467783830'
  scope: subscription()
}

resource networkContributorRoleDef 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  scope: subscription()
}

// Only need these if the existing role assignments don't already exist in the target sub
resource contributor 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid('1ES Resource Management Generic Contributor', oneESId, subscription().id)
  properties: {
    roleDefinitionId: contributorRoleDef.id
    principalId: oneESId
    principalType: 'ServicePrincipal'
  }
}

resource managedIdentityOperator 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid('1ES Resource Management MI Operator', oneESId, subscription().id)
  properties: {
    roleDefinitionId: managedIdentityOpRoleDef.id
    principalId: oneESId
    principalType: 'ServicePrincipal'
  }
}

resource networkContributor 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid('1ES Resource Management Network Contributor', oneESId, subscription().id)
  properties: {
    roleDefinitionId: networkContributorRoleDef.id
    principalId: oneESId
    principalType: 'ServicePrincipal'
  }
}

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: agentIdentityName
  scope: resourceGroup(resourceGroupName)
}

resource agentContributor 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid('Node SIG Agent Generic Contributor', agentIdentity.id, subscription().id)
  properties: {
    roleDefinitionId: contributorRoleDef.id
    principalId: agentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource agentStorageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid('Node SIG Agent Storage Blob Data Contributor', agentIdentity.id, subscription().id)
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDef.id
    principalId: agentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
