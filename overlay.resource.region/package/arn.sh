#!/bin/bash
set -e

echo "Grant autoupgrader data sender permission to ARN event grid domain"

# only assign in regions where ARN event grid domain exists
if az resource show --ids ${ARN_EVENTGRIDDOMAIN_ID} &> /dev/null ; then
    AUTOUPGRADER_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}autoupgrader"

    ASSIGNEE=$(az identity show --name ${AUTOUPGRADER_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

    # Grant data sender permission to ARN event grid domain
    az role assignment create --role "${EVENTGRID_DATA_SENDER_ROLE}" \
                        --assignee-object-id "${ASSIGNEE}"        \
                        --scope "${ARN_EVENTGRIDDOMAIN_ID}"
else
    echo "EventGrid not available in ${DEPLOYENV} in ${CLOUDENV}"
fi