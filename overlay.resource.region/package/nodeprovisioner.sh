#!/bin/bash
set -ex

NODE_PROVISIONER_USER_ASSIGNED_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}nodeprovisioner"

ASSIGNEE=$(az identity show --name "${NODE_PROVISIONER_USER_ASSIGNED_IDENTITY_NAME}"         \
                            --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}"        \
                            --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"    \
                            --query principalId -o tsv 2>/dev/null)


# Grant access to regional toggle storage
az role assignment create --role "${STORAGE_BLOB_DATA_READER_ROLE}" \
                        --assignee-object-id "${ASSIGNEE}" \
                        --scope "${REGIONAL_STORAGE_ID}"
                        
echo "Grant node provisioner permission to service bus"
source ./common.servicebus.sh
grant_sb_data_owner "$ASSIGNEE" "$NODEPROVISIONER_NAMESPACE_NAME"

# Grant access to HCP MachinePool service
echo "Update DB permission"
source ./common.sql.func.sh
echo "Getting current MSI objectId for machinepool"
export EV2_MSI_OBJECTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query principalId -o tsv 2>/dev/null || echo "")
export EV2_MSI_CLIENTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query clientId -o tsv 2>/dev/null || echo "")
export DB_NAME="machinepool"
export DB_ROLE="${HCP_DB_ROLE}"
export IDENTITY_CLIENTID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "${NODE_PROVISIONER_USER_ASSIGNED_IDENTITY_NAME}" --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" --query clientId -o tsv 2>/dev/null)
export MSI_DISPLAYNAME="${RESOURCE_NAME_PREFIX}aksoverlay-msi-operator"
export SERVICE_MSI_NAME="${NODE_PROVISIONER_USER_ASSIGNED_IDENTITY_NAME}"
export SQLADDRESS="${HCP_REGIONALSQLNAME}.${SQLSERVER_DATABASE_SUFFIX}"
export SQL_ADADMIN_ID=$(az sql server ad-admin list --subscription "${HCP_REGIONAL_SQL_SUBSCRIPTION_ID}" -g "${HCP_REGIONAL_SQL_RESOURCE_GROUP_NAME}" -s "${HCP_REGIONALSQLNAME}" --query [].sid --output tsv)

add_msi_to_sql "${HCP_REGIONALSQLNAME}"

# Grant reader access to sig gallery in glob
# there are still some manual steps needed for the code to work in ff, mc, etc
# will update the code once the manual steps are done
if [[ "${CLOUDENV}" != "gb" ]]; then
  echo "Skipping SIG gallery role assignment in ${CLOUDENV} cloud"
  exit 0
fi

if [[ -z "${SIG_SUBSCRIPTION_ID}" ]]; then
  # test and dev environments don't have SIG subscription id set
  if [[ "${DEPLOYENV}" == "prod" || "${DEPLOYENV}" == "staging" || "${DEPLOYENV}" == "int" ]]; then
    echo "SIG_SUBSCRIPTION_ID is not set in ${CLOUDENV} cloud ${DEPLOYENV} environment"
    exit 1
  else
    echo "SIG_SUBSCRIPTION_ID is not set in ${CLOUDENV} cloud ${DEPLOYENV} environment, skipping SIG gallery role assignment"
    exit 0
  fi
fi

# This function is copied from vhd/package/common.sh
# Note: The OS_SKU is read from the field offer_name in the publishing-info json (eg. Ubuntu, CBLMariner, AzureLinux, Windows)
function set_rg_and_sig_from_os_sku() {
    if [[ $# -lt 1 ]]; then
    echo "set_rg_and_sig_from_os_sku requires at least 1 arguments: os_sku and optional suffix"
    exit 1
  fi

  local os_sku=$1
  local suffix=$2

  if [ ${os_sku} != 'Ubuntu' ] && [ ${os_sku} != 'CBLMariner' ] && [ ${os_sku} != 'AzureLinux' ] && [ ${os_sku} != 'Windows' ]; then
    echo "Invalid os_sku ${os_sku} found"
    exit 1
  fi

  rg_name="AKS-${os_sku}"
  gallery_name="AKS${os_sku}"

  if [[ ! -z "${suffix}" ]]; then
    rg_name="${rg_name}-${suffix}"
    # this was an unfortunate error in original edge zone implementation,
    # but the galleries are in use and we can't easily change them
    # (haven't tried though, could be easier than expected)
    if [[ "${suffix}" == "EdgeZone" ]]; then
      gallery_name="${gallery_name}${suffix}"
    else
      gallery_name="${gallery_name}_${suffix}"
    fi
  fi
}

OS_SKUS=("Ubuntu" "CBLMariner" "AzureLinux" "Windows")
echo "az account show" && az account show

# for each os sku, assign node provisioner permission to SIG gallery
for OS_SKU in "${OS_SKUS[@]}"
do
    set_rg_and_sig_from_os_sku "${OS_SKU}" "${RESOURCE_SUFFIX}" || exit $?
    SIG_ID=$(az sig show --subscription ${SIG_SUBSCRIPTION_ID} --resource-group "${rg_name}" --gallery-name "${gallery_name}" --query id --output tsv)
    if [ -n "$SIG_ID" ]; then
        echo "Grant node provisioner permission to SIG gallery ${gallery_name} in resource group ${rg_name}"
        az role assignment create --role "Reader" \
            --assignee "$ASSIGNEE" \
            --scope "$SIG_ID"
    fi
done