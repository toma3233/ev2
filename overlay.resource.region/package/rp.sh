#!/bin/bash
set -e

echo "Grant rp read permission to toggle storage account"

RP_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}resource-provider"
OVERLAY_RESOURCE_GROUP_NAME="${OVERLAY_RESOURCE_GROUP_NAME:-"${RESOURCE_NAME_PREFIX}overlay-${REGION}"}"
OVERLAY_GLOBAL_RESOURCE_GROUP_NAME="${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global"

ASSIGNEE=$(az identity show --name "${RP_USER_ASSIGNED_IDENTITY_NAME}"         \
                            --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}"        \
                            --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"    \
                            --query principalId -o tsv 2>/dev/null)

OM_LEGACY_ETCD_STORAGE_ID="/subscriptions/${OM_LEGACY_STORAGE_ACCOUNT_REGION_SUBSCRIPTION_ID}/resourceGroups/${OM_LEGACY_ETCD_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${OM_LEGACY_ETCD_BACKUP_STORAGE_ACCOUNT_NAME}"
OM_ETCD_STORAGE_ID="/subscriptions/${OM_ETCD_STORAGE_ACCOUNT_SUBSCRIPTION_ID}/resourceGroups/${OM_ETCD_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${OM_ETCD_BACKUP_STORAGE_ACCOUNT_NAME}"

# TODO(hbc): support this in E2E
if [[ "${DEPLOYENV}" == "e2e" ]];
then
  # we only have one storage account in e2e
  echo "assign the role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE} to ${ASSIGNEE} in this scope ${OM_ETCD_STORAGE_ID}"
  az role assignment create \
    --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE} \
    --assignee-object-id ${ASSIGNEE}              \
    --scope ${OM_ETCD_STORAGE_ID}

  echo "assign the role ${STORAGE_ACCOUNT_CONTRIBUTOR_ROLE} to ${ASSIGNEE} in this scope ${OM_ETCD_STORAGE_ID}"
  az role assignment create \
    --role ${STORAGE_ACCOUNT_CONTRIBUTOR_ROLE} \
    --assignee-object-id ${ASSIGNEE}              \
    --scope ${OM_ETCD_STORAGE_ID}

  echo "assign the role ${STORAGE_ACCOUNT_KEY_OPERATOR_ROLE} to ${ASSIGNEE} in this scope ${OM_ETCD_STORAGE_ID}"
  az role assignment create \
    --role ${STORAGE_ACCOUNT_KEY_OPERATOR_ROLE} \
    --assignee-object-id ${ASSIGNEE}              \
    --scope ${OM_ETCD_STORAGE_ID}
else
  # Grant access to the etcd storage account
  if [[ "${OM_DEPLOY_LEGACY_ETCD_BACKUP_STORAGE_ACCOUNT}" == "true" ]]; then
    az role assignment create \
      --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE} \
      --assignee-object-id ${ASSIGNEE} \
      --scope ${OM_LEGACY_ETCD_STORAGE_ID}

    az role assignment create \
      --role ${STORAGE_ACCOUNT_CONTRIBUTOR_ROLE} \
      --assignee-object-id ${ASSIGNEE} \
      --scope ${OM_LEGACY_ETCD_STORAGE_ID}

    az role assignment create \
      --role ${STORAGE_ACCOUNT_KEY_OPERATOR_ROLE} \
      --assignee-object-id ${ASSIGNEE} \
      --scope ${OM_LEGACY_ETCD_STORAGE_ID}
  fi

  az role assignment create \
    --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE} \
    --assignee-object-id ${ASSIGNEE}              \
    --scope ${OM_ETCD_STORAGE_ID}

  az role assignment create \
    --role ${STORAGE_ACCOUNT_CONTRIBUTOR_ROLE} \
    --assignee-object-id ${ASSIGNEE}              \
    --scope ${OM_ETCD_STORAGE_ID}

  az role assignment create \
    --role ${STORAGE_ACCOUNT_KEY_OPERATOR_ROLE} \
    --assignee-object-id ${ASSIGNEE}              \
    --scope ${OM_ETCD_STORAGE_ID}
fi

# Grant access to deployer stg
echo "Grant deployer read permission to storage account"

DEPLOYER_STORAGE_ACCOUNT_NAME="${RESOURCE_NAME_PREFIX_NODASH}aksdpl${REGION}"
DEPLOYER_STORAGE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${OVERLAY_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${DEPLOYER_STORAGE_ACCOUNT_NAME}"

# TODO(hbc): support this in E2E
if [[ "${DEPLOYENV}" != "e2e" ]];
then
  az role assignment create --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE}             \
                            --assignee-object-id ${ASSIGNEE}              \
                            --scope ${DEPLOYER_STORAGE_ID}
fi

echo "Grant permission to service bus"
source common.servicebus.sh
grant_sb_data_owner "$ASSIGNEE" "$SERVICEBUS_NAMESPACE_NAME"

#Grant access to regional toggle storage
echo "Grant access to regional toggle storage"
az role assignment create --role ${STORAGE_BLOB_DATA_READER_ROLE}              \
                        --assignee-object-id ${ASSIGNEE}              \
                        --scope ${REGIONAL_STORAGE_ID}

echo "Grant RP storage account blob data contributor to OIDC storage account"

OIDC_STORAGE_ACCOUNT_NAME="${RESOURCE_NAME_PREFIX_GLOBAL_NODASH}aksoic"
GLOBAL_OIDC_STORAGE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${OVERLAY_GLOBAL_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${OIDC_STORAGE_ACCOUNT_NAME}"
OIDC_STORAGE_ID="/subscriptions/${OVERLAY_RESOURCES_SUBSCRIPTION_ID}/resourceGroups/${OVERLAY_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${RESOURCE_NAME_PREFIX_NODASH}aksoic${REGION}"

# TODO(hbc): support this in E2E
if [[ "${DEPLOYENV}" != "e2e" ]];
then
  az role assignment create --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE} \
                            --assignee-object-id ${ASSIGNEE}             \
                            --scope ${OIDC_STORAGE_ID}
  az role assignment create --role ${STORAGE_BLOB_DATA_CONTRIBUTOR_ROLE} \
                            --assignee-object-id ${ASSIGNEE}             \
                            --scope ${GLOBAL_OIDC_STORAGE_ID}
fi

# Grant rp msi permission to keyvault hcp-{REGION} and hcp-{REGION}b/c/d/e
if [[ "${DEPLOYENV}" != "test" ]] && [[ "${DEPLOYENV}" != "e2e" ]]; then
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
  echo "${REGION} hcp kv and sub map: $HCP_REGIONAL_KV_WITH_SUFFIX_SUBSCRIPTION_IDS"
  kv_names=$(echo ${HCP_REGIONAL_KV_WITH_SUFFIX_SUBSCRIPTION_IDS} | jq -r '.[] | .keyvault')
  kv_names=($kv_names)
  for kv_name in "${kv_names[@]}"; do 
    sub_id=$(echo ${HCP_REGIONAL_KV_WITH_SUFFIX_SUBSCRIPTION_IDS} | jq --arg key $kv_name -r '.[] | select (.keyvault==$key) | .subscriptionid')
    echo "Grant rp msi permission to $kv_name under $sub_id"
    az keyvault set-policy --name "$kv_name" --object-id $ASSIGNEE --secret-permissions get --subscription $sub_id
    echo "Done for $kv_name"
  done
fi
