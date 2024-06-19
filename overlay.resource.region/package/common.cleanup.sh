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
OVERLAY_GROUP_RESOURCE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_NAME_PREFIX}overlay-${REGION}"
echo "OVERLAY_GROUP_RESOURCE_ID:$OVERLAY_GROUP_RESOURCE_ID"

#TODO clean up aksol-<REGION> after migrate mooncake s2s certs to aksrp-<REGION>

# TODO check if needed
# if [[ "${CLOUDENV}" == "gb" ]]; then
    # azureclientcfg is still referenced
    # az_keyvault_secret_delete "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" "${RESOURCE_NAME_PREFIX}aksdpl${REGION}" "azureclientcfg"
# fi

# clean up unneeded sql alerts
az_resource_delete "${OVERLAY_GROUP_RESOURCE_ID}/providers/Microsoft.Insights/metricAlerts/SQL%20DTU%20Percentage%20Average%20-%20Sev%203"
az_resource_delete "${OVERLAY_GROUP_RESOURCE_ID}/providers/Microsoft.Insights/metricAlerts/SQL%20DTU%20Percentage"

az_resource_delete "${OVERLAY_GROUP_RESOURCE_ID}/providers/Microsoft.KeyVault/vaults/${RESOURCE_NAME_PREFIX}aksld${REGION}"
