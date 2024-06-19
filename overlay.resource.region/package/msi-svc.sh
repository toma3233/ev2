#!/bin/bash
set -e

echo "Grant msi-feature-connector-svc read permission to toggle storage account"

MSI_CONNECTOR_SVC_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}msi-feature-connector-svc"

ASSIGNEE=$(az identity show --name ${MSI_CONNECTOR_SVC_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)


# Grant access to regional toggle storage
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}              \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID}

echo "Grant msi-feature-connector read permission to toggle storage account"

MSI_CONNECTOR_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}msi-feature-connector"

ASSIGNEE=$(az identity show --name ${MSI_CONNECTOR_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)


# Grant access to regional toggle storage
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}              \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID}
