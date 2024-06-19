#!/bin/bash
set -x
## TODO: merge with upload_to_lowside.sh?
[[ -z "${SOV_CLOUD_HUB_STORAGE_ACCOUNT}" ]] && echo "SOV_CLOUD_HUB_STORAGE_ACCOUNT is not set" && exit 1
[[ -z "${SOV_CLOUD_HUB_CONTAINER}" ]] && echo "SOV_CLOUD_HUB_CONTAINER is not set" && exit 1
[[ -z "${CLOUDENV}" ]] && echo "CLOUDENV is not set" && exit 1
[[ -z "${DEPLOYENV}" ]] && echo "DEPLOYENV is not set" && exit 1
[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1
[[ -z "${SIG_REGION}" ]] && echo "SIG_REGION is not set" && exit 1
[[ -z "${EV2_BUILDVERSION}" ]] && echo "EV2_BUILDVERSION is not set" && exit 1
source ./common.sh

function main() {
  echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
  az account set --subscription ${SIG_SUBSCRIPTION_ID}
  if [ ${CLOUDENV} != "ex" ] && [ ${CLOUDENV} != "rx" ] && [ ${CLOUDENV} != 'mc' ] && [ ${CLOUDENV} != 'ff' ]; then
    echo "${CLOUDENV} is not a sovereign cloud - exiting early"
    exit 1
  fi

  if [ $# -gt 0 ] && [ "$1" == "wait" ]; then
    wait_blob_copy
  else
    copy_blob || exit $?
  fi
}

function copy_blob() {
  echo "copying vhd blob resource to sovereign blob storage account..."
  for i in publishing-info*/*.json; do
    local vhd_source="$(cat $i | jq -r '.vhd_url')"
    local image_version="$(cat $i | jq -r '.image_version')"
    local image_definition_name="$(cat $i | jq -r '.sku_name')"
    # os_sku is passed in through offer_name in publishing-info
    local os_sku="$(cat $i | jq -r '.offer_name')"
    set_rg_and_sig_from_os_sku "${os_sku}" "${RESOURCE_SUFFIX}" || exit $?

    # ensure ResourceGroup and Storage Account and container
    ensure_resource_group ${SIG_REGION} ${rg_name} || exit $?
    ensure_storage_resources ${SIG_REGION} ${rg_name} ${SOV_CLOUD_HUB_STORAGE_ACCOUNT} ${SOV_CLOUD_HUB_CONTAINER} "Standard_LRS" || exit $?

    local blob_name="${gallery_name}_${image_definition_name}_${image_version}.vhd"
    local log_prefix="[$gallery_name/$image_definition_name/$image_version]"
    echo "${log_Prefix}: start copying ${vhd_source} to storage account: ${SOV_CLOUD_HUB_STORAGE_ACCOUNT}, container: ${SOV_CLOUD_HUB_CONTAINER}, blob ${blob_name}"
    copyStatus=$(az storage blob show \
      --name ${blob_name} \
      --container-name ${SOV_CLOUD_HUB_CONTAINER} \
      --account-name ${SOV_CLOUD_HUB_STORAGE_ACCOUNT} \
      --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.status')
    
    if [ "${copyStatus}" == "success" ] || [ "${copyStatus}" == "pending" ]; then
        echo "${log_Prefix}: blob ${blob_name} has been copied or is in an active copy operation (status = ${copyStatus}) - skipping"
        continue
    fi
    az storage blob copy start \
      --destination-blob ${blob_name} \
      --destination-container ${SOV_CLOUD_HUB_CONTAINER} \
      --account-name ${SOV_CLOUD_HUB_STORAGE_ACCOUNT} \
      --subscription ${SIG_SUBSCRIPTION_ID} \
      --source-uri ${vhd_source} || exit 1
  done
}

function wait_blob_copy() {
  for i in publishing-info*/*.json; do
    local image_version="$(cat $i | jq -r '.image_version')"
    local image_definition_name="$(cat $i | jq -r '.sku_name')"
    # os_sku is passed through offer_name in publishing-info
    local os_sku="$(cat $i | jq -r '.offer_name')"
    set_rg_and_sig_from_os_sku "${os_sku}" "${RESOURCE_SUFFIX}" || exit $?

    local blob_name="${gallery_name}_${image_definition_name}_${image_version}.vhd"
    local log_prefix="[$gallery_name/$image_definition_name/$image_version]"
    echo "${log_Prefix}: checking copy status of ${blob_name}"
    while [[ "$(az storage blob show \
      --name ${blob_name} \
      --container-name ${SOV_CLOUD_HUB_CONTAINER} \
      --account-name ${SOV_CLOUD_HUB_STORAGE_ACCOUNT} \
      --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.status')" != "success" ]]; do
      echo "${log_prefix}: Waiting for copy to storage account: ${SOV_CLOUD_HUB_STORAGE_ACCOUNT}, container: ${SOV_CLOUD_HUB_CONTAINER}, blob ${blob_name}"
      sleep 120
    done
    echo "${log_prefix}: Copy done for storage account: ${SOV_CLOUD_HUB_STORAGE_ACCOUNT}, container: ${SOV_CLOUD_HUB_CONTAINER}, blob ${blob_name}"
  done

}

main "$@"