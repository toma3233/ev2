#!/bin/bash
set -euo pipefail

echo "Grant cost-analysis-scraper data sender permission on the event hub"

COST_ANALYSIS_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}cost-analysis-scraper"

ASSIGNEE=$(az identity show --name "${COST_ANALYSIS_USER_ASSIGNED_IDENTITY_NAME}"    \
                            --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}"        \
                            --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"    \
                            | jq -r .principalId)

# Grant send access on data hub to the cost-analysis-scraper user
az role assignment create --role "${EVENT_HUBS_DATA_SENDER_ROLE}" \
                        --assignee-object-id "${ASSIGNEE}"        \
                        --scope "${COSTANALYSIS_DATA_EVENTHUB}"

az role assignment create --role "${EVENT_HUBS_DATA_SENDER_ROLE}" \
                        --assignee-object-id "${ASSIGNEE}"        \
                        --scope "${COSTANALYSIS_DATA_EVENTHUB_UNPARTIITONED}"

# Grant receive access on data hub to the PAV2 user
az role assignment create --role "${EVENT_HUBS_DATA_RECEIVER_ROLE}" \
                        --assignee-object-id "${COSTANALYSIS_PAV2_OBJECTID}"        \
                        --scope "${COSTANALYSIS_DATA_EVENTHUB}"

az role assignment create --role "${EVENT_HUBS_DATA_RECEIVER_ROLE}" \
                        --assignee-object-id "${COSTANALYSIS_PAV2_OBJECTID}"        \
                        --scope "${COSTANALYSIS_DATA_EVENTHUB_UNPARTIITONED}"

# Grant send access on response hub to the PAV2 user
az role assignment create --role "${EVENT_HUBS_DATA_SENDER_ROLE}" \
                        --assignee-object-id "${COSTANALYSIS_PAV2_OBJECTID}"        \
                        --scope "${COSTANALYSIS_RESPONSE_EVENTHUB}"

az role assignment create --role "${EVENT_HUBS_DATA_SENDER_ROLE}" \
                        --assignee-object-id "${COSTANALYSIS_PAV2_OBJECTID}"        \
                        --scope "${COSTANALYSIS_RESPONSE_EVENTHUB_UNPARTITIONED}"
