#!/bin/bash

function grant_sb_data_owner() {
  local ASSIGNEE=$1
  local SERVICEBUS_NAME=$2
  local AKSBUS_TARGET_ID=""

  echo "Grant ${ASSIGNEE} Azure Service Bus Data Owner permission to ${SERVICEBUS_NAME}"

  local SERVICEBUS_DATA_OWNER_ROLE="090c5cfd-751d-490a-894a-3ce6f1109419"

# allow to override SB_RESOURCE_GROUP in e2e. use overlay_resource_group in real deployments
  if [ "${SB_RESOURCE_GROUP}" == "" ];
  then
    SB_RESOURCE_GROUP="${OVERLAY_RESOURCE_GROUP_NAME}"
  fi
  if [ "${SB_SUBSCRIPTION_ID}" == "" ];
  then
    SB_SUBSCRIPTION_ID="${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"
  fi


  AKSBUS_TARGET_ID=$(az servicebus namespace show --resource-group "${SB_RESOURCE_GROUP}" --name \
      "${SERVICEBUS_NAME}" --subscription ${SB_SUBSCRIPTION_ID} --query id -o tsv 2>/dev/null || echo "")

  if [ "${AKSBUS_TARGET_ID}" == "" ]; then
    echo "${SERVICEBUS_NAME} servicebus namespace not present in region: ${REGION} - subscription: ${SB_SUBSCRIPTION_ID} - resource group: ${SB_RESOURCE_GROUP}"
    exit 1
  fi

  az role assignment create --assignee-object-id "${ASSIGNEE}" \
                          --role "${SERVICEBUS_DATA_OWNER_ROLE}" \
                          --scope "${AKSBUS_TARGET_ID}"
}
