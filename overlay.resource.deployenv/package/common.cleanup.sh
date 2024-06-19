#!/bin/bash
set -euo pipefail

function az_resource_delete() {
    echo "Checking $1"
    if az resource show --ids $1 &> /dev/null ; then
        echo "Exist, deleting"
        az resource delete --ids $1
    else
        echo "Does not exist, skip"
    fi
}

function az_keyvault_secret_delete() {
    echo "Checking subscription $1, keyvault $2, secret $3"
    if az keyvault secret show --subscription $1 --vault-name $2 -n $3 -o none &> /dev/null ; then
        echo "Exist, deleting"
        az keyvault secret delete --subscription $1 --vault-name $2 -n $3 -o table
    else
        echo "Does not exist, skip"
    fi
}

echo "Ensure unused resources deleted"
OVERLAY_GLOBAL_GROUP_RESOURCE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_NAME_PREFIX}overlay-global"
echo "OVERLAY_GLOBAL_GROUP_RESOURCE_ID:$OVERLAY_GLOBAL_GROUP_RESOURCE_ID"

az_resource_delete "${OVERLAY_GLOBAL_GROUP_RESOURCE_ID}/providers/Microsoft.KeyVault/vaults/${RESOURCE_NAME_PREFIX}aksprogrollout"
