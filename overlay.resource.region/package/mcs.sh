#!/bin/bash
set -e

echo "Grant maintenanceconfigagent read permission to toggle storage account"

MAINTENANCECONFIG_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}maintenanceconfigagent"

ASSIGNEE=$(az identity show --name ${MAINTENANCECONFIG_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)


#Grant access to regional toggle storage
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}              \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID} 
