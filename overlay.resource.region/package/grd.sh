#!/bin/bash
set -e

source ./common.servicebus.sh
source ./common.sql.func.sh

echo "Grant guardrails read permission to toggle storage account"

GUARDRAILS_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}guardrails"


ASSIGNEE=$(az identity show --name ${GUARDRAILS_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

echo "Grant guardrails service bus data owner role"
grant_sb_data_owner "$ASSIGNEE" "$SERVICEBUS_NAMESPACE_NAME"
#Grant access to regional toggle storage
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}              \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID} 


echo "Update DB permission"
echo "Getting current MSI objectId"
export EV2_MSI_OBJECTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query principalId -o tsv 2>/dev/null || echo "")
export EV2_MSI_CLIENTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query clientId -o tsv 2>/dev/null || echo "")
export DB_NAME="safeguards"
export DB_ROLE="${HCP_DB_ROLE}"
export IDENTITY_CLIENTID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "${GUARDRAILS_USER_ASSIGNED_IDENTITY_NAME}" --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" --query clientId -o tsv 2>/dev/null)
export MSI_DISPLAYNAME="${RESOURCE_NAME_PREFIX}aksoverlay-msi-operator"
export SERVICE_MSI_NAME="${GUARDRAILS_USER_ASSIGNED_IDENTITY_NAME}"
export SQLADDRESS="${HCP_REGIONALSQLNAME}.${SQLSERVER_DATABASE_SUFFIX}"
export SQL_ADADMIN_ID=$(az sql server ad-admin list --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" -s "${HCP_REGIONALSQLNAME}" --query [].sid --output tsv)

add_msi_to_sql "${HCP_REGIONALSQLNAME}"
