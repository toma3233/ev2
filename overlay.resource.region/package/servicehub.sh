#!/bin/bash
set -e

echo "Grant servicehub MSI tag contributor and storage/blob data contributor permission to servicehub resource group"

SERVICEHUB_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}servicehub"

ASSIGNEE=$(az identity show --name ${SERVICEHUB_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

#Grant servicehub tag contributor permission to servicehub resource group
az role assignment create --role ${TAG_CONTRIBUTOR_ROLE}              \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${SERVICEHUB_RESOURCE_GROUP}

#Grant servicehub storage blob data contributor permission to servicehub resource group
az role assignment create --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE} \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${SERVICEHUB_RESOURCE_GROUP}

#Grant servicehub storage acct contributor permission to servicehub resource group
az role assignment create --role ${STORAGE_ACCOUNT_CONTRIBUTOR_ROLE} \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${SERVICEHUB_RESOURCE_GROUP}