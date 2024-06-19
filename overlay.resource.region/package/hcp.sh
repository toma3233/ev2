#!/bin/bash
set -e

source ./common.sql.func.sh

echo "[DEBUG] SQL env vars"
echo "HCP_REGIONAL_SQL_SUBSCRIPTION_ID: ${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}"
echo "HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME: ${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}"
echo "RP_SQL_SUBSCRIPTION_ID: ${RP_SQL_SUBSCRIPTION_ID}"
echo "RP_SQL_RESOURCE_GROUP_NAME: ${RP_SQL_RESOURCE_GROUP_NAME}"

echo "Grant hcp read permission to toggle storage account"

HCP_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}hcp"

#Probably duplicate of IDENTITY_OBJECTID but leaving to be consistent with other toggle assignments
ASSIGNEE=$(az identity show --name ${HCP_USER_ASSIGNED_IDENTITY_NAME}         \
                            --resource-group ${OVERLAY_RESOURCE_GROUP_NAME}        \
                            --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID}    \
                            | jq -r .principalId)

#Grant access to regional toggle storage
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}     \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID} 

if ! is_deploy_to_e2e; then # Don't need to worry about audit logs in E2E
  # Get System Assigned MI from Azure SQL Server
  SQL_SERVER_MI=$(az sql server show --resource-group ${OVERLAY_RESOURCE_GROUP_NAME} \
                                    --name ${HCP_REGIONALSQLNAME} \
                                    --query identity.principalId -o tsv)

  echo "SQL_SERVER_MI: ${SQL_SERVER_MI}"

  # Remove hyphens from the storage name
  STRIPPED_STORAGE_NAME=$(echo ${HCP_SQL_AUDIT_STORAGE_NAME} | tr -d -)

  echo "stripped_storage_name: ${STRIPPED_STORAGE_NAME}"

  STORAGE_SCOPE=$(az storage account show --name ${STRIPPED_STORAGE_NAME} \
                                          --resource-group ${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME} \
                                          --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query id -o tsv)

  # Get the storage endpoint from the storage account
  AUDIT_STORAGE_ENDPOINT=$(az storage account show -n ${STRIPPED_STORAGE_NAME} -g ${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME} --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query primaryEndpoints.blob -o tsv)

  echo "Storage Endpoint: ${AUDIT_STORAGE_ENDPOINT}"

  az role assignment create --role "ba92f5b4-2d11-453d-a403-e96b0029c9fe"     \
                          --assignee-object-id ${SQL_SERVER_MI}              \
                          --scope ${STORAGE_SCOPE}

  echo "Update SQL Audit settings"
  az sql server audit-policy update -g ${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME} \
                                    -n ${HCP_REGIONALSQLNAME} \
                                    --state Enabled \
                                    --bsts Enabled \
                                    --storage-endpoint "${AUDIT_STORAGE_ENDPOINT}" \
                                    --storage-key "" \
                                    --retention-days 90
fi

# Grant hcp msi permission to keyvault hcp-{REGION} and hcp-{REGION}b/c/d/e
if [[ "${DEPLOYENV}" != "test" ]] && ! is_deploy_to_e2e; then
  export UNDERLAYAPI_MSI_ID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" | jq -r .clientId)
  echo "MSI_OPERATOR_RESOURCE_ID       $MSI_OPERATOR_RESOURCE_ID"
  echo "UNDERLAYAPI_MSI_ID             $UNDERLAYAPI_MSI_ID"
  INFRAAPI_DIR="common/scripts/infraapi"
  if [ ! -e "$INFRAAPI_DIR" ]; then
      echo "Infra API folder ${INFRAAPI_DIR} not exists. Exit!!"
      exit 1
  fi
  source "$INFRAAPI_DIR/infraapi_utils.sh"
  HCP_REGIONAL_KV_WITH_SUFFIX_SUBSCRIPTION_IDS=$(list-provisioned-cx-underlays-sub-kv-map "${CLOUD_ENVIRONMENT}" "${DEPLOY_ENV}" "${REGION}" msi)
  kv_names=$(echo ${HCP_REGIONAL_KV_WITH_SUFFIX_SUBSCRIPTION_IDS} | jq -r '.[] | .keyvault')
  kv_names=($kv_names)
  for kv_name in "${kv_names[@]}"; do 
    sub_id=$(echo ${HCP_REGIONAL_KV_WITH_SUFFIX_SUBSCRIPTION_IDS} | jq --arg key $kv_name -r '.[] | select (.keyvault==$key) | .subscriptionid')
    echo "Grant hcp msi permission to $kv_name under $sub_id"
    az keyvault set-policy --name "$kv_name" --object-id $ASSIGNEE --secret-permissions get --subscription $sub_id
    echo "Done for $kv_name"
  done
fi

echo "Update DB permission"

echo "Getting current MSI objectId"
export EV2_MSI_OBJECTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query principalId -o tsv 2>/dev/null || echo "")
export EV2_MSI_CLIENTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query clientId -o tsv 2>/dev/null || echo "")
export DB_NAME="${HCP_DBNAME}"
export DB_ROLE="${HCP_DB_ROLE}"
export IDENTITY_CLIENTID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "${RESOURCE_NAME_PREFIX}hcp" --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" --query clientId -o tsv 2>/dev/null)
export MSI_DISPLAYNAME="${RESOURCE_NAME_PREFIX}aksoverlay-msi-operator"
export SERVICE_MSI_NAME="${RESOURCE_NAME_PREFIX}hcp"
export SQLADDRESS="${HCP_REGIONALSQLNAME}.${SQLSERVER_DATABASE_SUFFIX}"
export SQL_ADADMIN_ID=$(az sql server ad-admin list --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" -s "${HCP_REGIONALSQLNAME}" --query [].sid --output tsv)

add_msi_to_sql "${HCP_REGIONALSQLNAME}"

if [[ "${CLOUDENV}" == "gb" && "${DEPLOYENV}" == "prod" && "${REGION}" == "eastus2euap" ]];
then
  echo "adding msi to sql for failover group target server"
  export SQLADDRESS="${HCP_TARGETSQLNAME}.${SQLSERVER_DATABASE_SUFFIX}"
  export SQL_ADADMIN_ID=$(az sql server ad-admin list --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" -s "${HCP_TARGETSQLNAME}" --query [].sid --output tsv)

  echo "Setting SQL AD-Admin for target server as ${MSI_DISPLAYNAME}"
  add_msi_to_sql "${HCP_TARGETSQLNAME}"
fi

echo "Finished granting HCP Regional DB Permissions"

