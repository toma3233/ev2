#!/bin/bash

function grant_eg_data_sender() {
    local ASSIGNEE=$1
    local EVENTGRID_NAME=$2

    echo "Grant ${ASSIGNEE} Azure Event Grid Data Sender permission to ${EVENTGRID_NAME}"

    local EVENTGRID_DATA_SENDER_ROLE="d5a91429-5739-47e2-a06b-3470a27159e7"

    EVENTGRID_DOMAIN_ID=$(az eventgrid domain show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "${EVENTGRID_NAME}" --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" --query id -o tsv 2>/dev/null || echo "")

    if [ "${EVENTGRID_DOMAIN_ID}" != "" ]; then
        az role assignment create --assignee-object-id "${ASSIGNEE}" \
                            --role "${EVENTGRID_DATA_SENDER_ROLE}" \
                            --scope "${EVENTGRID_DOMAIN_ID}" \
                            --assignee-principal-type ServicePrincipal
    else
        echo "${EVENTGRID_NAME} event grid domain not present in region: ${REGION} - cloud: ${CLOUDENV} - env: ${DEPLOYENV}"
    fi
}