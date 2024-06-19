#!/bin/bash
set -e

echo "Assign dnc and rp MSI Contributor role to dnc cosmos db"

DNC_COSMOS_NAME="${RESOURCE_NAME_PREFIX_NODASH}dnc${REGION}"

DNC_MSI_NAME="${RESOURCE_NAME_PREFIX}dnc"
DNC_MSI_OBJECT_ID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
  "${DNC_MSI_NAME}" --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query principalId -o tsv 2>/dev/null || echo "")


DNC_COSMOS_RESOURCE_ID=$(az cosmosdb show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
  "${DNC_COSMOS_NAME}" --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query id -o tsv 2>/dev/null || echo "")
#is this the same as the above?
DNC_SCOPE="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${OVERLAY_RESOURCE_GROUP_NAME}/providers/Microsoft.DocumentDB/databaseAccounts/${DNC_COSMOS_NAME}"

#az role definition list --name "DocumentDB Account Contributor"
# "description": "Lets you manage DocumentDB accounts, but not access to them.",
DNC_ACCOUNT_CONTRIBUTOR_ROLE="5bd9cd88-fe45-4216-938b-f97437e15450"

if [ "${DNC_COSMOS_RESOURCE_ID}" == "" ]; then
  echo "${DNC_COSMOS_NAME} cosmos db not present in region - ${REGION} in resource group - ${OVERLAY_RESOURCE_GROUP_NAME}"
  exit 0
fi

if [ "${DNC_MSI_OBJECT_ID}" == "" ]; then
  echo "${DNC_MSI_NAME} identity not present in region - ${REGION} in resource group - ${OVERLAY_RESOURCE_GROUP_NAME}"
  exit 1
fi


# Need to use --assignee-object-id instead of --assignee else az cli will try to call graph api and it will return insufficient priviledges error
# https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/databases#documentdb-account-contributor
az role assignment create --assignee-object-id ${DNC_MSI_OBJECT_ID} --scope ${DNC_SCOPE} --role ${DNC_ACCOUNT_CONTRIBUTOR_ROLE}
# we do this to try and get access to Microsoft.DocumentDB/locations/operationsStatus/read to watch table creation and throughput settings
az role assignment create --assignee-object-id ${DNC_MSI_OBJECT_ID} --scope ${DNC_SCOPE} --role "Reader"

#relies on failures short circuiting or we get down. time Rmove in future
az role assignment delete --assignee ${DNC_MSI_OBJECT_ID} --scope ${DNC_SCOPE} --role "Contributor" || echo "giving up on best effort removal of dnc contributor"


#remove this in future. RP doesn't call cosmos directly and subnet handler  runs under dnc msi.
RP_MSI_NAME="${RESOURCE_NAME_PREFIX}resource-provider"
RP_MSI_OBJECT_ID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
  "${RP_MSI_NAME}" --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query principalId -o tsv 2>/dev/null || echo "")

if [ "${RP_MSI_OBJECT_ID}" == "" ]; then
  echo "${RP_MSI_NAME} identity not present in region - ${REGION} in resource group - ${OVERLAY_RESOURCE_GROUP_NAME}"
  exit 1
fi

az role assignment delete --assignee ${RP_MSI_OBJECT_ID} --scope ${DNC_SCOPE} --role "Contributor"  || echo "giving up on best effort removal of rp contributor"
