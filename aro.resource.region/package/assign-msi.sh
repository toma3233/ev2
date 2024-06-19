#!/bin/bash
set -euo pipefail

echo "CLOUD_ENVIRONMENT                     $CLOUD_ENVIRONMENT"
echo "DEPLOY_ENV                            $DEPLOY_ENV"
echo "REGION                                $REGION"
echo "MSI_OPERATOR_RESOURCE_ID              $MSI_OPERATOR_RESOURCE_ID"

INFRA_API_DIR="common/scripts/infraapi"

if [ ! -e "$INFRA_API_DIR" ]; then
    echo "Infra API folder ${INFRA_API_DIR} not found. Exiting."
    exit 1
fi

# The infra utils script relies on UNDERLAYAPI_MSI_ID being set
UNDERLAYAPI_MSI_ID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" | jq -r .clientId)
echo "UNDERLAYAPI_MSI_ID                     $UNDERLAYAPI_MSI_ID"

# Import functions for retrieving underlays
source "$INFRA_API_DIR/infraapi_utils.sh"

function assign_msi_to_underlay {
    local  underlay_subscription_id=$1
    local  underlay_resource_group=$2
    
    echo "Validating svc underlay ${underlay_resource_group} subscription ${underlay_subscription_id}..."
    
    local vmss_objects=$(az vmss list -g "${underlay_resource_group}" --subscription "${underlay_subscription_id}" -o json | jq -r '[.[] | select(.name| contains("master")|not)]') || true
    local vmss_names=($(echo "${vmss_objects}" | jq -r '.[] | .name')) || true
    
    if [ ${#vmss_names[@]} -eq 0 ]; then
        echo "vmss not found in resource group ${underlay_resource_group} subscription ${underlay_subscription_id}."
        exit 1
    fi    

    for vmss_name in "${vmss_names[@]}"
    do    
        echo "vmss name: ${vmss_name}"
        
        az vmss identity assign \
            --subscription "${underlay_subscription_id}" \
            --resource-group "${underlay_resource_group}" \
            --name "${vmss_name}" \
            --identities "/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_NAME_PREFIX}aro-billing-${REGION}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${RESOURCE_NAME_PREFIX}arobillingmsi-${REGION}-v5"

        echo "Assign identities done."
    done
}

SVC_CLUSTERS=$(list-svc-underlays "${CLOUD_ENVIRONMENT}" "${DEPLOY_ENV}" "${REGION}" "msi")
SVC_UNDERLAYS=($(echo "${SVC_CLUSTERS}" | jq -r .name))
SVC_SUBSCRIPTIONS=($(echo "${SVC_CLUSTERS}" | jq -r .subscriptionid))

for i in "${!SVC_UNDERLAYS[@]}"; do
    assign_msi_to_underlay "${SVC_SUBSCRIPTIONS[$i]}" "${SVC_UNDERLAYS[$i]}"
done