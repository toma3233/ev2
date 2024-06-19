#!/bin/bash
set -e

function is_deploy_to_e2e {
  case ${DEPLOY_ENV} in
    e2e | corptest | corpdev)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

function add_msi_to_sql {
  echo "Adding MSI to SQL"
  if ! is_deploy_to_e2e && [ "${SQL_ADADMIN_ID}" != "${EV2_MSI_OBJECTID}" ]; then
    echo "Setting SQL AD-Admin as ${MSI_DISPLAYNAME}"
    # create is idempotent put
    az sql server ad-admin create -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" --server $1 -i "${EV2_MSI_OBJECTID}" -u "${MSI_DISPLAYNAME}"
  fi

  echo "Setting permissions for ${SERVICE_MSI_NAME} for object ${IDENTITY_CLIENTID}"
  az sql server firewall-rule create -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" --server $1 --name "pipeline_rule" --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
  export SQL_SCRIPT=$(envsubst < ./common.msi_to_sql.sql)
  export HOME=/root # https://github.com/microsoft/go-sqlcmd/issues/279

  if is_deploy_to_e2e; then
    echo "Executing E2E: sqlcmd -d ${DB_NAME} -U ${AKS_E2E_SQL_USER} -S ${SQLADDRESS} --authentication-method=ActiveDirectoryManagedIdentity -Q"
    az sql server ad-admin create -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" --server $1 -i "${AKS_E2E_SQL_USER_OBJECTID}" -u "${AKS_E2E_SQL_USER_MSI_NAME}"
    sqlcmd -d "${DB_NAME}" -U "${AKS_E2E_SQL_USER}" -S "${SQLADDRESS}" --authentication-method=ActiveDirectoryManagedIdentity -Q "$SQL_SCRIPT"
  else
    sqlcmd -d "${DB_NAME}" -U "${EV2_MSI_CLIENTID}" -S "${SQLADDRESS}" --authentication-method=ActiveDirectoryManagedIdentity -Q "$SQL_SCRIPT"
  fi
  az sql server firewall-rule delete -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" --server $1 --name "pipeline_rule"

  if ! is_deploy_to_e2e && [ "{CLOUDENV}" == "gb" ]; then
    echo "Setting ESGJIT permissions for ${DB_NAME}"
    ## We need to set ESGJIT as the AD-Admin for the SQL Server
    az sql server ad-admin create -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" --server $1 -i "27dccd23-623d-4c70-8bfd-024a26c8f7c0" -u "ESGJIT-AKSDevOps"
  fi
}