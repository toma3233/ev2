#!/bin/bash
set -e

echo "Grant deployer read permission to storage account"
DEPLOYER_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}deployer"
DEPLOYER_USER_CX_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}deployer-cx"
DEPLOYER_USER_SVC_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}deployer-svc"

OVERLAY_RESOURCE_GROUP_NAME="${RESOURCE_NAME_PREFIX}overlay-${REGION}"
STORAGE_ACCOUNT_NAME="${RESOURCE_NAME_PREFIX_NODASH}aksdpl${REGION}"
STORAGE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${OVERLAY_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"

ASSIGNEE=$(az identity show --name ${DEPLOYER_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}             \
                          --assignee-object-id ${ASSIGNEE}              \
                          --scope ${STORAGE_ID}

MSI_OPETATOR_ASSIGNEE=$(az identity show --ids ${MSI_OPERATOR_RESOURCE_ID}    \
                        | jq -r .principalId)

az role assignment create --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE}             \
                          --assignee-object-id ${MSI_OPETATOR_ASSIGNEE}              \
                          --scope ${STORAGE_ID}

CX_ASSIGNEE=$(az identity show --name ${DEPLOYER_USER_SVC_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}             \
                          --assignee-object-id ${CX_ASSIGNEE}              \
                          --scope ${STORAGE_ID}

SVC_ASSIGNEE=$(az identity show --name ${DEPLOYER_USER_CX_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}             \
                          --assignee-object-id ${SVC_ASSIGNEE}              \
                          --scope ${STORAGE_ID}
