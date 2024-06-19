#!/bin/bash
set -x

[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1
[[ -z "${SIG_REGION}" ]] && echo "SIG_REGION is not set" && exit 1
[[ -z "${MSI_OPERATOR_RESOURCE_ID}" ]] && echo "MSI_OPERATOR_RESOURCE_ID is not set" && exit 1
[[ -z "${EV2_BUILDVERSION}" ]] && echo "EV2_BUILDVERSION is not set" && exit 1
source ./common.sh

IMAGE_BUILDER_TEMPLATE_FILE_NAME="image_builder_template.json"
IMAGE_BUILDER_ARM64_TEMPLATE_FILE_NAME="image_builder_template_arm64.json"
IMAGE_BUILDER_INPUT_FILE_NAME="image_builder_input.json"
IMAGE_BUILDER_RG_NAME="AKS-Image-Builder-${EV2_BUILDVERSION//./}"
IMAGE_BUILDER_TEMPLATE_RESOURCE_TYPE="Microsoft.VirtualMachineImages/imageTemplates"

function main() {
    echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
    az account set --subscription ${SIG_SUBSCRIPTION_ID}

    [ $# -ne 1 ] && echo "optimize_with_prefetch.sh requires one sub-command to be specified" && exit 1

    sub_command=$1
    if [[ "${sub_command}" == "optimizeBlobs" ]]; then
        optimize_blobs || exit $?
    elif [[ "${sub_command}" == "beginOptimizedBlobOverwrite" ]]; then
        begin_optimized_blob_overwrite || exit $?
    elif [[ "${sub_command}" == "waitOptimizedBlobOverwrite" ]]; then
        wait_optimized_blob_overwrite || exit $?
    else
        echo "unrecognized sub-command '${sub_command}', must be one of: optimizeBlobs, beginOptimizedBlobOverwrite, and waitOptimizedBlobOverwrite"
        exit 1
    fi
}

function optimize_blobs() {
    ensure_resource_group ${SIG_REGION} ${IMAGE_BUILDER_RG_NAME} || exit $?
    rg_id=$(az group show -g ${IMAGE_BUILDER_RG_NAME} | jq -r .id)
    az tag create --resource-id $rg_id --tags SIGReleaseStep=PrefetchOptimization

    for pi in publishing-info*/*.json; do
        local vhd_source="$(cat $pi | jq -r '.vhd_url')"
        local os_name="$(cat $pi | jq -r '.os_name')"
        local image_version="$(cat $pi | jq -r '.image_version')"
        local image_definition_name="$(cat $pi | jq -r '.sku_name')"
        local image_arch="$(cat $pi | jq -r '.image_architecture')"
        local hyperv_generation="$(cat $pi | jq -r '.hyperv_generation')"
        local captured_sig_resource_id="$(cat $pi | jq -r '.captured_sig_resource_id')"
        local log_prefix="[$image_definition_name/$image_version]"


        set_unique_vhd_version ${log_prefix} ${vhd_source} || exit $?
        [[ "${DEPLOYENV}" == "test" ]] && vhd_source="https://imagebuilderinputs.blob.core.windows.net/vhds/${unique_vhd_version}.vhd"
        
        template_name="${image_definition_name}_${unique_vhd_version}"
        template_id=$(az image builder show -g ${IMAGE_BUILDER_RG_NAME} -n ${template_name} | jq -r .id)
        need_new_template="false"
        if [ -z "$template_id" ]; then
            need_new_template="true"
        else
            template_info=$(az image builder show -g ${IMAGE_BUILDER_RG_NAME} -n ${template_name})
            template_provisioning_state=$(echo "${template_info}" | jq -r .provisioningState)
            if [[ "${template_provisioning_state,,}" == "failed" ]]; then
                delete_template ${IMAGE_BUILDER_RG_NAME} ${template_name} ${log_prefix}
                need_new_template="true"
            else
                latest_run_provisioning_state=$(echo "${template_info}" | jq -r .lastRunStatus.runState)
                if [[ "${latest_run_provisioning_state,,}" == "failed" ]]; then
                    delete_template ${IMAGE_BUILDER_RG_NAME} ${template_name} ${log_prefix}
                    need_new_template="true"
                fi
            fi
        fi

        if [[ "${need_new_template}" == "true" ]]; then
            if [[ "${image_arch,,}" == "arm64" ]]; then
                sed -e "s#<region>#${SIG_REGION}#g" \
                -e "s#<imageBuilderIdentityUri>#${MSI_OPERATOR_RESOURCE_ID}#g" \
                -e "s#<captured_sig_resource_id>#${captured_sig_resource_id}#g" \
                ${IMAGE_BUILDER_ARM64_TEMPLATE_FILE_NAME} > ${IMAGE_BUILDER_INPUT_FILE_NAME}
            else
                managed_image_name="ITMI_${image_definition_name}_${unique_vhd_version}"
                ensure_mananged_image ${IMAGE_BUILDER_RG_NAME} ${managed_image_name} ${image_definition_name} ${image_version} ${os_name} ${hyperv_generation} ${vhd_source%%\?*} ${log_prefix} || exit $?

                sed -e "s#<region>#${SIG_REGION}#g" ${IMAGE_BUILDER_TEMPLATE_FILE_NAME} > ${IMAGE_BUILDER_INPUT_FILE_NAME}
                sed -i -e "s#<imageBuilderIdentityUri>#${MSI_OPERATOR_RESOURCE_ID}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
                sed -i -e "s#<managedImageId>#${managed_image_id}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
            fi

            # create the image builder template, this will go and create the staging resource group where image builder will run
            # we create a new staging resource group for each VHD we get from the weekly build pipeline
            echo "${log_prefix}: creating image builder template ${template_name}..."
            az resource create -n ${template_name} \
                --properties @${IMAGE_BUILDER_INPUT_FILE_NAME} --is-full-object \
                --api-version 2022-07-01 \
                --resource-type ${IMAGE_BUILDER_TEMPLATE_RESOURCE_TYPE} \
                --resource-group ${IMAGE_BUILDER_RG_NAME} || exit $?

            echo "${log_prefix}: image builder template ${template_name} has been created, starting run..."
            az image builder run -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} --no-wait
        else
            echo "${log_prefix}: skipping creation and invokation for template ${template_name}..."
        fi
    done

    declare -a failed_templates=()
    for pi in publishing-info*/*.json; do
        local vhd_source="$(cat $pi | jq -r '.vhd_url')"
        local os_name="$(cat $pi | jq -r '.os_name')"
        local image_version="$(cat $pi | jq -r '.image_version')"
        local image_definition_name="$(cat $pi | jq -r '.sku_name')"
        local image_arch="$(cat $pi | jq -r '.image_architecture')"
        local hyperv_generation="$(cat $pi | jq -r '.hyperv_generation')"
        local log_prefix="[$image_definition_name/$image_version]"
        
        set_unique_vhd_version ${log_prefix} ${vhd_source} || exit $?
        template_name="${image_definition_name}_${unique_vhd_version}"

        echo "waiting for image builder template ${template_name} to finish running..."
        az image builder wait -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} --custom "lastRunStatus.runState!='Running'"

        template_run_state=$(az image builder show -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} | jq -r '.lastRunStatus.runState')
        if [[ "${template_run_state}" != "Succeeded" ]]; then
            echo "${template_name} failed to run successfully, finished with state: '${template_run_state}'"
            failed_templates+=(${template_name})
            continue
        fi

        echo "image builder template ${template_name} completed successfully"
    done

    if [ ${#failed_templates[@]} -gt 0 ]; then
        echo "the following image builder templates did not run successfully: ${failed_templates[@]}"
        exit 1
    fi
}

function begin_optimized_blob_overwrite() {
    for pi in publishing-info*/*.json; do
        local vhd_source="$(cat $pi | jq -r '.vhd_url')"
        local image_version="$(cat $pi | jq -r '.image_version')"
        local image_definition_name="$(cat $pi | jq -r '.sku_name')"
        local image_arch="$(cat $pi | jq -r '.image_architecture')"
        local log_prefix="[$image_definition_name/$image_version]"

        set_unique_vhd_version ${log_prefix} ${vhd_source} || exit $?
        [[ "${DEPLOYENV}" == "test" ]] && vhd_source="https://imagebuilderinputs.blob.core.windows.net/vhds/${unique_vhd_version}.vhd"

        template_name="${image_definition_name}_${unique_vhd_version}"
        staging_rg_name=$(az resource show -n ${template_name} \
            -g ${IMAGE_BUILDER_RG_NAME} \
            --resource-type ${IMAGE_BUILDER_TEMPLATE_RESOURCE_TYPE} \
            --api-version 2022-02-14 | jq -r '.properties.exactStagingResourceGroup')
        staging_rg_name=${staging_rg_name##*/}
        optimized_blob_url=$(az image builder show-runs -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} | jq -r '.[-1].artifactUri')

        set_storage_details_from_vhd_blob_url ${optimized_blob_url} ${log_prefix} || exit $?
        source_storage_account_name=${storage_account_name}
        source_storage_container_name=${storage_container_name}
        source_blob_name=${vhd_blob_name}
        set_sas_url ${staging_rg_name} ${source_storage_account_name} ${source_storage_container_name} ${source_blob_name}
        optimized_sas_url=${sas_url}

        set_storage_details_from_vhd_blob_url ${vhd_source} ${log_prefix} || exit $?
        destination_storage_account_name=${storage_account_name}
        destination_storage_container_name=${storage_container_name}
        destination_blob_name=${vhd_blob_name}
        copy_source_to_destination_blob ${destination_storage_account_name} \
            ${destination_storage_container_name} \
            ${destination_blob_name} \
            ${optimized_sas_url} \
            ${staging_rg_name} \
            ${log_prefix} || exit $?
    done
}

function wait_optimized_blob_overwrite() {
    for pi in publishing-info*/*.json; do
        local vhd_source="$(cat $pi | jq -r '.vhd_url')"
        local image_version="$(cat $pi | jq -r '.image_version')"
        local image_definition_name="$(cat $pi | jq -r '.sku_name')"
        local image_arch="$(cat $pi | jq -r '.image_architecture')"
        local log_prefix="[$image_definition_name/$image_version]"

        set_unique_vhd_version ${log_prefix} ${vhd_source} || exit $?
        [[ "${DEPLOYENV}" == "test" ]] && vhd_source="https://imagebuilderinputs.blob.core.windows.net/vhds/${unique_vhd_version}.vhd"

        template_name="${image_definition_name}_${unique_vhd_version}"
        staging_rg_name=$(az resource show -n ${template_name} \
            -g ${IMAGE_BUILDER_RG_NAME} \
            --resource-type ${IMAGE_BUILDER_TEMPLATE_RESOURCE_TYPE} \
            --api-version 2022-02-14 | jq -r '.properties.exactStagingResourceGroup')
        staging_rg_name=${staging_rg_name##*/}
        optimized_blob_url=$(az image builder show-runs -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} | jq -r '.[-1].artifactUri')

        set_storage_details_from_vhd_blob_url ${vhd_source} ${log_prefix} || exit $?
        destination_storage_account_name=${storage_account_name}
        destination_storage_container_name=${storage_container_name}
        destination_blob_name=${vhd_blob_name}
        wait_vhd_to_storage_account_and_container ${destination_storage_account_name} \
            ${destination_storage_container_name} \
            ${destination_blob_name} \
            ${staging_rg_name} \
            ${log_prefix} || exit $?
    done
}

# currently not being used, will we need it when running in PROD to deliver the image builder output VHDs to a destination account/container?
function copy_source_to_destination_blob() {
    if [ $# -ne 6 ]; then
        echo "unexpected number of arguments to copy image builder output VHD to temp storage"
        exit 1
    fi
    local destination_storage_account_name=$1
    local destination_storage_container_name=$2
    local destination_blob_name=$3
    local vhd_source=$4
    local staging_rg_name=$5
    local log_prefix=$6

    copy_info=$(az storage blob show \
        --name ${destination_blob_name} \
        --container-name ${destination_storage_container_name} \
        --account-name ${destination_storage_account_name} \
        --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq '.properties.copy')
    copy_source=$(echo "${copy_info}" | jq -r '.source')

    if [[ "${copy_source}" != "null" ]]; then
        # this blob has previously been copied to from somewhere else
        set_storage_details_from_vhd_blob_url ${copy_source} ${log_prefix} || exit $?
        source_storage_account_name=${storage_account_name}
        # attempt to show the storage account under the assumption it's within the template's staging resource group
        source_storage_account_info=$(az storage account show -g ${staging_rg_name} -n ${source_storage_account_name} --subscription ${SIG_SUBSCRIPTION_ID})
        if [ -n "${source_storage_account_info}" ]; then
            # double-check the tags on the storage account to guarantee it contains the optimized blob
            source_storage_account_created_by=$(echo "${source_storage_account_info}" | jq -r '.tags.createdby')
            if [[ "${source_storage_account_created_by}" == "AzureVMImageBuilder" ]]; then
                copy_status=$(echo "${copy_info}" | jq -r '.status')
                if [[ "${copy_status}" == "success" ]] || [[ "${copy_status}" == "pending" ]]; then
                    # if the copy is already done or is currently in-progress, exit early
                    echo "${log_prefix}: blob ${destination_blob_name} has been copied or is in an active copy operation from ${copy_source} (status = ${copy_status}) - skipping"
                    return 0
                fi
            fi
        fi
    fi

    echo "${log_prefix}: beginning copy operation for blob ${destination_blob_name} to ${destination_storage_account_name}/${destination_storage_container_name}"
    az storage blob copy start \
        --destination-blob ${destination_blob_name} \
        --destination-container ${destination_storage_container_name} \
        --account-name ${destination_storage_account_name} \
        --subscription ${SIG_SUBSCRIPTION_ID} \
        --source-uri ${vhd_source} || exit $?
}

function wait_vhd_to_storage_account_and_container() {
    if [ $# -ne 5 ]; then
        echo "unexpected number of arguments to copy image builder output VHD to temp storage"
        exit 1
    fi
    local destination_storage_account_name=$1
    local destination_storage_container_name=$2
    local destination_blob_name=$3
    local staging_rg_name=$4
    local log_prefix=$5
    
    copy_source=$(az storage blob show \
        --name ${destination_blob_name} \
        --container-name ${destination_storage_container_name} \
        --account-name ${destination_storage_account_name} \
        --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.source')
    if [[ "${copy_source}" != "null" ]]; then
        set_storage_details_from_vhd_blob_url ${copy_source} ${log_prefix} || exit $?
        source_storage_account_name=${storage_account_name}
        source_storage_account_info=$(az storage account show -g ${staging_rg_name} -n ${source_storage_account_name} --subscription ${SIG_SUBSCRIPTION_ID})
        if [ -z "${source_storage_account_info}" ] || [[ "$(echo "${source_storage_account_info}" | jq -r .tags.createdby)" != "AzureVMImageBuilder" ]]; then
            echo "${log_prefix}: copy operation in progress for blob ${destination_blob_name} is occuring from an unexpected source: ${copy_source},\
            expected source storage account ${source_storage_account_name} to be in a template's staging resource group and have proper tagging"
            exit 1
        fi
    fi

    while [[ "$(az storage blob show \
      --name ${destination_blob_name} \
      --container-name ${destination_storage_container_name} \
      --account-name ${destination_storage_account_name} \
      --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.status')" != "success" ]]; do
      echo "${log_prefix}: waiting for copy to storage account: ${destination_storage_account_name}, container: ${destination_storage_container_name}, blob: ${destination_blob_name}"
      sleep 60s
    done

    echo "${log_prefix}: copy done for storage account: ${destination_storage_account_name}, container: ${destination_storage_container_name}, blob: ${destination_blob_name}"
}

function ensure_mananged_image() {
    if [ $# -ne 8 ]; then
        echo "unexpected number of arguments to ensure managed image"
        exit 1
    fi
    local rg_name=$1
    local managed_image_name=$2
    local image_definition_name=$3
    local image_version=$4
    local os_name=$5
    local hyperv_generation=$6
    local vhd_source=$7
    local log_prefix=$8

    echo "${log_prefix}: check managed image existence: ${rg_name}/${managed_image_name}"
    managed_image_id=$(az image show --resource-group ${rg_name} --name ${managed_image_name} -ojson | jq -r ".id")
    if [ -z "$managed_image_id" ]; then
        # create the image from the vhd source URI
        # this currently assumes that the $vhd_source points to a VHD that has already been properly copied to the current subscription in some storage account/container
        az image create --resource-group ${rg_name} --name ${managed_image_name} --os-type ${os_name} --hyper-v-generation ${hyperv_generation} --source ${vhd_source} || exit $?
        until [ -n "$managed_image_id" ]; do
            echo "${log_prefix}: sleeping for 30s before getting managed image ${rg_name}/${managed_image_name}..."
            sleep 30s
            managed_image_id=$(az image show --resource-group ${rg_name} --name ${managed_image_name} -o json | jq -r ".id")
        done
        echo "${log_prefix}: managed image has been created with uri ${managed_image_id}"
    else
        echo "${log_prefix}: managed image ${managed_image_id} found"
    fi
}

function delete_template() {
    if [ $# -ne 3 ]; then
        echo "unexpected number of arguments to delete image builder template"
        exit 1
    fi
    local rg_name=$1
    local template_name=$2
    local log_prefix=$3

    id=$(az image builder show -n ${template_name} -g ${rg_name} | jq -r .id)
    if [ -n "$id" ]; then
        echo "${log_prefix}: found existing AIB template with name ${template_name}, removing before proceeding with new template..."
        az image builder delete -n ${template_name} -g ${rg_name}
    fi
}

# currently doing this in TEST for demo purposes, will this be needed in PROD?
function set_sas_url() {
    if [ $# -ne 4 ]; then
        echo "unexpected number of arugments to copy blob to set SAS URL suffix from storage account details"
        exit 1
    fi
    local rg_name=$1
    local storage_account_name=$2
    local storage_container_name=$3
    local blob_name=$4

    set +x
    connection_string=$(az storage account show-connection-string --resource-group ${rg_name} --name ${storage_account_name} | jq -r '.connectionString')
    [ -z "${connection_string}" ] && echo "an error occured when generating connection string for storage account: ${rg_name}/${storage_account_name}" && exit 1
    # set the SAS to expire after 180 minutes - it should only be used within the context of the linux VHD SIG release pipeline
    expiry=$(date -u -d "180 minutes" '+%Y-%m-%dT%H:%MZ')
    sas_token=$(az storage container generate-sas --connection-string ${connection_string} --name ${storage_container_name} --permissions lr --expiry ${expiry} | tr -d '"')
    [ -z "${sas_token}" ] && echo "an error occured when generating SAS token for ${rg_name}/${storage_account_name}/${storage_container_name}/${blob_name}" && exit 1
    sas_url="https://${storage_account_name}.blob.core.windows.net/${storage_container_name}/${blob_name}?${sas_token}"
    set -x
    
    echo "generated SAS url for blob: ${rg_name}/${storage_account_name}/${storage_container_name}/${blob_name}"
}

main "$@"