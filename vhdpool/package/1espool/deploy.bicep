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
param location string = resourceGroup().location

var isMariner = endsWith(resourceNameSuffix, 'mariner')
var agentIdentityName = 'nodesig-agent-identity${resourceNameSuffix}'
var vnetName = 'nodesig-pool-vnet${resourceNameSuffix}'
var poolName = 'nodesig${env}-pool${resourceNameSuffix}'
var sku = 'Standard_D4ds_v4'

// Base 1ES Image Resource IDs
var ubuntu2004GalleryVersionResourceId = '/subscriptions/723b64f0-884d-4994-b6de-8960d049cb7e/resourceGroups/CloudTestImages/providers/Microsoft.Compute/galleries/CloudTestGallery/images/MMSUbuntu20.04-Secure/versions/latest'
var marinerV2Gen2BaseImage = '/MicrosoftCBLMariner/cbl-mariner/cbl-mariner-2-gen2/latest'
var marinerAgentImageBaseLocation = 'westus3'

var vmProviderProperties = {
  EnableAcceleratedNetworking: true
  vssAdminPermissions: 'Inherit'
  // EnableAutomaticPredictions: true
}

var poolSettings = {
  prod: {
    maxPoolSize: 36 // 36 agents allows us to run two concurrent builds of all 18 VHDs
    resourcePredictions: [
      {
        '11:00': 9  // 7 AM EST Sunday
      }
      {
        // Make sure we have enough agents for a couple full concurrent builds before the weekly trigger time, slowly scale back throughout the day
        '08:01': 36 // 3:01 AM EST Monday - the official weekly builds are triggered automatically at around 4AM EST Monday
        '14:00': 18 // 9 AM EST Monday
      }
      {
        '11:00': 18  // 7 AM EST Tuesday
      }
      {
        '11:00': 18  // 7 AM EST Wednesday
      }
      {
        '11:00': 18  // 7 AM EST Thursday
      }
      {
        '11:00': 18 // 7 AM EST Friday
      }
      {
        '11:00': 9 // 7 AM EST Saturday
      }
    ]
  }
  test: {
    maxPoolSize: 36 // 54 agents allows us to run three concurrent builds of all 18 VHDs
    resourcePredictions: [
      {
        '11:00': 9  // 7 AM EST Sunday
      }
      {
        // Extend the primary operating hours on Mondays to account for potential debugging of the weekly build
        '8:01': 36  // 3:01 AM EST Monday
        '23:00': 18 // 7 PM EST Monday
      }
      {
        '11:00': 36 // 7 AM EST Tuesday
        '23:00': 18 // 7 PM EST Tuesday
      }
      {
        '11:00': 36 // 7 AM EST Wednesday
        '23:00': 18 // 7 PM EST Wednesday
      }
        {
        '11:00': 36 // 7 AM EST Thursday
        '23:00': 18 // 7 PM EST Thursday
      }
      {
        '11:00': 36 // 7 AM EST Friday
        '23:00': 18 // 7 PM EST Friday
      }
      {
        '11:00': 9  // 7 AM EST Saturday
      }
    ]
  }
}

resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: agentIdentityName
}

resource vnet 'Microsoft.Network/virtualNetworks@2020-08-01' existing = {
  name: vnetName
}

resource ubuntuAgentImage 'Microsoft.CloudTest/images@2020-05-07' = if (!isMariner) {
  name: 'nodesig-agent-image'
  location: location
  properties: {
    imageType: 'SharedImageGallery'
    resourceId: ubuntu2004GalleryVersionResourceId
  }
}

resource marinerAgentImage 'Microsoft.CloudTest/images@2020-05-07' = if (isMariner) {
  name: 'nodesig-agent-image-mariner'
  location: marinerAgentImageBaseLocation
  properties: {
    imageType: 'Managed'
    baseImage: marinerV2Gen2BaseImage
    artifacts: [
      {
        name: 'linux-bash-command'
        parameters: {
          command: 'sudo tdnf -y install git make tar rpm rpm-build wget curl moby-engine moby-cli pigz golang-1.17.13 gcc glibc-devel binutils kernel-headers qemu-img cdrkit parted dosfstools rsync dnf sudo'
        }
      }
      {
        name: 'linux-bash-command'
        parameters: {
          command: 'sudo tdnf -y install dotnet-sdk-6.0 acl bison cpio createrepo dnf-utils dosfstools gawk jq powershell azure-cli'
        }
      }
    ]
    publishingProfile: {
      targetRegions: [
        {
          name: marinerAgentImageBaseLocation
          replicas: 1
        }
        {
          name: location
          replicas: 1
        }
      ]
    }
  }
}

resource hostedPool 'Microsoft.CloudTest/hostedpools@2020-05-07' = {
  name: poolName
  location: location
  identity: {
    type: 'userAssigned'
    userAssignedIdentities:  {
      '${agentIdentity.id}': {}
    }
  }
  properties: {
    organization: 'https://dev.azure.com/msazure'
    sku: {
      name: sku
      tier: 'Premium'
    }
    images: [
      {
        subscriptionId: subscription().subscriptionId
        imageName: isMariner ? marinerAgentImage.name : ubuntuAgentImage.name
        poolBufferPercentage: '100'
      }
    ]
    maxPoolSize: poolSettings[env].maxPoolSize
    agentProfile: {
      type: 'Stateless'
      resourcePredictions: poolSettings[env].resourcePredictions
    }    
    vmProviderProperties: vmProviderProperties
    networkProfile: {
      natGatewayIpAddressCount: 0
      peeredVirtualNetworkResourceId: vnet.id
    }
  }
}
