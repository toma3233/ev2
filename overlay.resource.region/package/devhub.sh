#!/bin/bash
set -e

echo "[DEBUG] SQL env vars"
echo "HCP_REGIONAL_SQL_SUBSCRIPTION_ID: ${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}"
echo "HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME: ${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}"
echo "HCP_REGIONALSQLNAME: ${HCP_REGIONALSQLNAME}"
echo "DEVHUB_DBNAME: ${DEVHUB_DBNAME}"
echo "Update DevHub DB permission"

export DEVHUB_DBNAME="devhub"

echo "Getting current MSI objectId"
source ./common.sql.func.sh
export EV2_MSI_OBJECTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query principalId -o tsv 2>/dev/null || echo "")
export EV2_MSI_CLIENTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query clientId -o tsv 2>/dev/null || echo "")
export DB_NAME="${DEVHUB_DBNAME}"
export DB_ROLE="${HCP_DB_ROLE}"
export IDENTITY_CLIENTID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "${RESOURCE_NAME_PREFIX}devhub" --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" --query clientId -o tsv 2>/dev/null)
export MSI_DISPLAYNAME="${RESOURCE_NAME_PREFIX}aksoverlay-msi-operator"
export SERVICE_MSI_NAME="${RESOURCE_NAME_PREFIX}devhub"
export SQLADDRESS="${HCP_REGIONALSQLNAME}.${SQLSERVER_DATABASE_SUFFIX}"
export SQL_ADADMIN_ID=$(az sql server ad-admin list --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" -s "${HCP_REGIONALSQLNAME}" --query [].sid --output tsv)

add_msi_to_sql "${HCP_REGIONALSQLNAME}"

echo "Finished granting DevHub Regional DB Permissions"
