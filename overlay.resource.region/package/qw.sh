#!/bin/bash
set -e

QW_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}queuewatcher"

ASSIGNEE=$(az identity show --name ${QW_IDENTITY_NAME} \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME} \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} \
                            --query "principalId" \
                            -o tsv)

source ./common.servicebus.sh
grant_sb_data_owner "$ASSIGNEE" "$SERVICEBUS_NAMESPACE_NAME"