#!/bin/bash
set -x

[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1
[[ -z "${SIG_REGION}" ]] && echo "SIG_REGION is not set" && exit 1
[[ -z "${DEPLOYENV}" ]] && echo "DEPLOYENV is not set" && exit 1
[[ -z "${STORAGE_ACCOUNT_TYPE}" ]] && echo "STORAGE_ACCOUNT_TYPE is not set" && exit 1
source ./common.sh

[[ "${DEPLOYENV}" != "test" ]] && echo "can only run copy for image builder in test environment" && exit 1

temp_storage_account_name="imagebuilderinputs"
temp_storage_container_name="vhds"

function main() {
    echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
    az account set --subscription ${SIG_SUBSCRIPTION_ID}

    rg_name="AKS-Image-Builder"
    ensure_resource_group ${SIG_REGION} ${rg_name} || exit $?

    if [ "$1" == "wait" ]; then
        wait_blob_copy
    else
        copy_blob ${rg_name} || exit $?
    fi
}

function copy_blob() {
    local rg_name=$1

    # Ensure the temporary storage account and container
    ensure_storage_resources ${SIG_REGION} ${rg_name} ${temp_storage_account_name} ${temp_storage_container_name} ${STORAGE_ACCOUNT_TYPE} || exit $?
    
    for pi in publishing-info*/*.json; do
        local vhd_url="$(cat $pi | jq -r '.vhd_url')"
        local image_version="$(cat $pi | jq -r '.image_version')"
        local image_definition_name="$(cat $pi | jq -r '.sku_name')"
        local log_prefix="[$image_definition_name/$image_version]"

        # copy the blob to a new storage account and container in the current sub
        set_unique_vhd_version ${log_prefix} ${vhd_url} || exit $?
        local blob_name="${unique_vhd_version}.vhd"
        blob_exists=$(az storage blob exists -n ${blob_name} --container-name ${temp_storage_container_name} --account-name ${temp_storage_account_name} | jq -r '.exists')
        if [[ "${blob_exists}" == "true" ]]; then
            echo "${log_prefix}: ${blob_name} already exists in ${temp_storage_account_name}/${temp_storage_container_name}, skipping copy..."
            continue
        fi

        echo "${log_Prefix}: start copying ${vhd_url} to blob ${blob_name} in storage account: ${temp_storage_account_name}, container: ${temp_storage_container_name}"
        copyStatus=$(az storage blob show \
            --name ${blob_name} \
            --container-name ${temp_storage_container_name} \
            --account-name ${temp_storage_account_name} \
            --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.status')
        
        if [ "${copyStatus}" == "success" ] || [ "${copyStatus}" == "pending" ]; then
            echo "${log_Prefix}: blob ${blob_name} has been copied or is in an active copy operation (status = ${copyStatus}) - skipping"
        else
            az storage blob copy start \
                --destination-blob ${blob_name} \
                --destination-container ${temp_storage_container_name} \
                --account-name ${temp_storage_account_name} \
                --subscription ${SIG_SUBSCRIPTION_ID} \
                --source-uri ${vhd_url} || exit $?
        fi
    done
}

function wait_blob_copy() {
    for pi in publishing-info*/*.json; do
        local vhd_url="$(cat $pi | jq -r '.vhd_url')"
        local image_version="$(cat $pi | jq -r '.image_version')"
        local image_definition_name="$(cat $pi | jq -r '.sku_name')"
        local log_prefix="[$image_definition_name/$image_version]"

        set_unique_vhd_version ${log_prefix} ${vhd_url} || exit $?
        local blob_name="${unique_vhd_version}.vhd"

        while [[ "$(az storage blob show \
        --name ${blob_name} \
        --container-name ${temp_storage_container_name} \
        --account-name ${temp_storage_account_name} \
        --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.status')" != "success" ]]; do
        echo "${log_prefix}: waiting for copy to storage account: ${temp_storage_account_name}, container: ${temp_storage_container_name}, blob ${blob_name}"
        sleep 90
        done

        echo "${log_prefix}: copy done for storage account: ${temp_storage_account_name}, container: ${temp_storage_container_name}, blob: ${blob_name}"
    done
}

main "$@"