#!/bin/bash
set -e

echo "Grant progressive rollout read permission to its vault certification"

PROGRESSIVE_ROLLOUT_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}aksprogrollout"
OVERLAY_RESOURCE_GROUP_NAME="${OVERLAY_RESOURCE_GROUP_NAME:-"${RESOURCE_NAME_PREFIX}overlay-${REGION}"}"

ASSIGNEE=$(az identity show --name ${PROGRESSIVE_ROLLOUT_USER_ASSIGNED_IDENTITY_NAME}    \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

#Grant access to key vault certification
az keyvault set-policy \
    --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" \
    --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" \
    --name "${RESOURCE_NAME_PREFIX}akspr${REGION}" \
    --secret-permissions get \
    --certificate-permissions get \
    --object-id "${ASSIGNEE}"