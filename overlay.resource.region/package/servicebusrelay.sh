#!/bin/bash
set -e

SERVICEBUS_RELAY_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}servicebusrelay"

ASSIGNEE=$(az identity show --name "${SERVICEBUS_RELAY_USER_ASSIGNED_IDENTITY_NAME}"         \
                            --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}"        \
                            --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"    \
                            --query principalId -o tsv 2>/dev/null)


echo "Grant permission to service bus"
source common.servicebus.sh
grant_sb_data_owner "$ASSIGNEE" "$SERVICEBUS_NAMESPACE_NAME"
