#!/bin/bash
set -e

echo "Grant jitcontroller read permission to toggle storage account"

jitcontroller_identities=(jitcontroller jitcontroller-svc)
for identity in "${jitcontroller_identities[@]}"; do
    JITCONTROLLER_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}${identity}"

    ASSIGNEE=$(az identity show --name ${JITCONTROLLER_USER_ASSIGNED_IDENTITY_NAME}         \
                                --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                                --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                                | jq -r .principalId)

    #Grant access to regional toggle storage
    az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}              \
                            --assignee-object-id ${ASSIGNEE}              \
                            --scope ${REGIONAL_STORAGE_ID} 
done
