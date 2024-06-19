#!/bin/bash
set -e

PRIVATE_CONNECT_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}private-connect-controller"

ASSIGNEE=$(az identity show --name ${PRIVATE_CONNECT_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

echo "Grant private connect read permission to toggle storage account"

#Grant access to regional toggle storage
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}              \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID}
