#!/bin/bash
set -x
[[ -z "${SOV_CLOUD_HUB_STORAGE_ACCOUNT}" ]] && echo "SOV_CLOUD_HUB_STORAGE_ACCOUNT is not set" && exit 1
[[ -z "${SOV_CLOUD_HUB_CONTAINER}" ]] && echo "SOV_CLOUD_HUB_CONTAINER is not set" && exit 1
[[ -z "${STORAGE_ACCOUNT_TYPE}" ]] && echo "STORAGE_ACCOUNT_TYPE is not set" && exit 1 
[[ -z "${CLOUDENV}" ]] && echo "CLOUDENV is not set" && exit 1
[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1

source ./common.sh

function main() {
    echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
    az account set --subscription ${SIG_SUBSCRIPTION_ID}
    if [ ${CLOUDENV} != "ex" ] && [ ${CLOUDENV} != "rx" ] && [ ${CLOUDENV} != 'mc' ] && [ ${CLOUDENV} != 'ff' ]; then
        echo "${CLOUDENV} is not a sovereign cloud - exiting early"
        exit 1
    fi
    for i in publishing-info*/*.json; do
        local image_version="$(cat $i | jq -r '.image_version')"
        local image_definition_name="$(cat $i | jq -r '.sku_name')"
        local os_sku="$(cat $i | jq -r '.offer_name')"

        set_rg_and_sig_from_os_sku "${os_sku}" "${RESOURCE_SUFFIX}" || exit $?

        local blob_name="${gallery_name}_${image_definition_name}_${image_version}.vhd"
        local log_prefix="[$gallery_name/$image_definition_name/$image_version]"
        echo "${log_Prefix}: deleting ${blob_name} from storage account ${SOV_CLOUD_HUB_STORAGE_ACCOUNT}"
        
        copyStatus=$(az storage blob show \
        --name ${blob_name} \
        --container-name ${SOV_CLOUD_HUB_CONTAINER} \
        --account-name ${SOV_CLOUD_HUB_STORAGE_ACCOUNT} \
        --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.status')
        if [ "${copyStatus}" != "success" ]; then
            echo "${log_Prefix}: blob ${blob_name} has not been copied successfully - skipping"
            continue
        fi

        az storage blob delete \
        --name ${blob_name} \
        --container-name ${SOV_CLOUD_HUB_CONTAINER} \
        --account-name ${SOV_CLOUD_HUB_STORAGE_ACCOUNT} \
        --subscription ${SIG_SUBSCRIPTION_ID} || exit 1
    done
}

main
