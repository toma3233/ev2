#!/bin/bash
set -e

OVERLAYMGR_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}overlaymgr"
RP_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}resource-provider"

# Initialize constants and resource names
ADDONACR="${RESOURCE_NAME_PREFIX_GLOBAL_NODASH}aksaddoncharts"
ADDONTESTACR="${RESOURCE_NAME_PREFIX_GLOBAL_NODASH}aksaddontestcharts"
ADDONADAPTERACR="${RESOURCE_NAME_PREFIX_GLOBAL_NODASH}aksaddonadaptercharts"

echo "ADDONACR ${ADDONACR}"
echo "ADDONTESTACR ${ADDONTESTACR}"
echo "ADDONADAPTERACR ${ADDONADAPTERACR}"

# Function to provision regional replication for ACR
function ProvisionReplication() {
  ACRNAME=$1
  acrep=$( az acr replication show \
    --name ${REGION} \
    --registry ${ACRNAME} \
    --resource-group "${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global" \
    --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} ) || true

  if [[ -z "${acrep}" ]]; then
    if [[ "${ZONE_REDUNDANT}" == "true" ]]; then
      ZONE_REDUNDANCY="Enabled"
    else
      ZONE_REDUNDANCY="Disabled"
    fi

    echo "Adding regional ${REGION} replication for ACR ${ACRNAME}"
    az acr replication create \
       --location ${REGION} \
       --registry ${ACRNAME} \
       --resource-group "${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global" \
       --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} \
       --zone-redundancy ${ZONE_REDUNDANCY} \
       || echo "Couldn't apply replication, but this isn't a blocking requirement for a new region. Continuing..."
  else
    echo "Regional replication already exists, skipping"
  fi
}

echo "Adding regional replication for aksaddoncharts ACR"
ProvisionReplication ${ADDONACR}

echo "Adding regional replication for aksaddontestcharts ACR"
ProvisionReplication ${ADDONTESTACR}

echo "Adding regional replication for aksaddonadaptercharts ACR"
ProvisionReplication ${ADDONADAPTERACR}

echo "Grant overlaymgr msi pull access to aksaddonadaptercharts"
ASSIGNEE=$(az identity show --name ${OVERLAYMGR_USER_ASSIGNED_IDENTITY_NAME} \
              --resource-group ${OVERLAY_RESOURCE_GROUP_NAME} \
              --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} \
              | jq -r .principalId)

az role assignment create --role "AcrPull" \
   --assignee-object-id ${ASSIGNEE} \
   --scope "/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global/providers/Microsoft.ContainerRegistry/registries/${ADDONADAPTERACR}"


ASSIGNEE=$(az identity show --name "${RP_USER_ASSIGNED_IDENTITY_NAME}"         \
                            --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}"        \
                            --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"    \
                            --query principalId -o tsv 2>/dev/null)

echo "Grant rp msi push access to ${ADDONACR}"
az role assignment create --role "AcrPush" \
   --assignee-object-id ${ASSIGNEE} \
   --scope "/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global/providers/Microsoft.ContainerRegistry/registries/${ADDONACR}"

echo "Grant rp msi push access to ${ADDONTESTACR}"
az role assignment create --role "AcrPush" \
   --assignee-object-id ${ASSIGNEE} \
   --scope "/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global/providers/Microsoft.ContainerRegistry/registries/${ADDONTESTACR}"

echo "Grant rp msi push access to ${ADDONADAPTERACR}"
az role assignment create --role "AcrPush" \
   --assignee-object-id ${ASSIGNEE} \
   --scope "/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global/providers/Microsoft.ContainerRegistry/registries/${ADDONADAPTERACR}"