#!/bin/bash
set -e

echo "Grant regional looper read permission to toggle storage account"

RL_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}regionallooper"


ASSIGNEE=$(az identity show --name ${RL_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

#Grant access to regional toggle storage
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE} \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID} 

echo "Grant regional looper read/write permission to dns zone"

az role assignment create --role ${DNS_ZONE_CONTRIBUTOR_ROLE} \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${DNS_ZONE_ID} || echo 'error updating rbac'

source ./common.servicebus.sh
grant_sb_data_owner "$ASSIGNEE" "$SERVICEBUS_NAMESPACE_NAME"