#!/bin/bash
set -euo pipefail

OIC_STORAGE_NAME="${RESOURCE_NAME_PREFIX_NODASH}aksoic${REGION}"
OIC_STORAGE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${OVERLAY_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${OIC_STORAGE_NAME}"
EV2_MSI_OBJECTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query principalId -o tsv 2>/dev/null || echo "")
if [ "${EV2_MSI_OBJECTID}" == "" ]; then
  echo "failed to show msi operator ${MSI_OPERATOR_RESOURCE_ID}"
  exit 1
fi
az role assignment create --role "Storage Blob Data Contributor" --assignee-object-id "${EV2_MSI_OBJECTID}" --scope "${OIC_STORAGE_ID}"

FILE=/tmp/oic-smoke-test.txt
echo ok > $FILE
az storage blob upload --account-name ${OIC_STORAGE_NAME} \
                        --container-name "00000000-0000-0000-0000-000000000001" \
                        --name "00000000-0000-0000-0000-000000000000/smoke-test" \
                        --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} \
                        --file $FILE \
                        --auth-mode login \
                        --overwrite


ASSIGNEE=$(az identity show --name ${RESOURCE_NAME_PREFIX}oic                   \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}     \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} \
                            | jq -r .principalId)
OIC_STORAGE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${OVERLAY_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${OIC_STORAGE_NAME}"

echo "assign the role ${STORAGE_ACCOUNT_CONTRIBUTOR_ROLE} to ${ASSIGNEE} in this scope ${OIC_STORAGE_ID}"
az role assignment create \
  --role ${STORAGE_ACCOUNT_CONTRIBUTOR_ROLE} \
  --assignee-object-id ${ASSIGNEE}           \
  --scope ${OIC_STORAGE_ID}

if [[ "${DEPLOYENV}" == "test" || "${DEPLOYENV}" == "int" || "${DEPLOYENV}" == "staging" ]]; then
    az storage blob service-properties update --auth-mode login --account-name $OIC_STORAGE_NAME --static-website
fi
