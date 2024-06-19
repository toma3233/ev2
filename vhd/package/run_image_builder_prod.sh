#!/bin/bash
set -x

[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1
[[ -z "${SIG_REGION}" ]] && echo "SIG_REGION is not set" && exit 1
[[ -z "${DEPLOYENV}" ]] && echo "DEPLOYENV is not set" && exit 1
[[ -z "${CLOUDENV}" ]] && echo "CLOUDENV is not set" && exit 1
[[ -z "${MSI_OPERATOR_RESOURCE_ID}" ]] && echo "MSI_OPERATOR_RESOURCE_ID is not set" && exit 1
[[ -z "${EV2_BUILDVERSION}" ]] && echo "EV2_BUILDVERSION is not set" && exit 1
source ./common.sh

[[ "${CLOUDENV}" != "gb" ]] && echo "will not run in any cloud environment other than public cloud" && exit 1

IMAGE_BUILDER_TEMPLATE_FILE_NAME="image_builder_to_sig_template.json"
IMAGE_BUILDER_INPUT_FILE_NAME="image_builder_input.json"
PREFETCH_IMAGE_VERSION="222.222.223"

function main() {
    echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
    az account set --subscription ${SIG_SUBSCRIPTION_ID}

    # ensure the manually set resource group - we use a new resource group in which to build the templates
    IMAGE_BUILDER_RG_NAME="AKS-Image-Builder-${EV2-BUILDVERSION//./}"
    ensure_resource_group ${SIG_REGION} ${IMAGE_BUILDER_RG_NAME} || exit $?

    declare -a template_names=()
    for pi in publishing-info*/*.json; do
        local vhd_source="$(cat $pi | jq -r '.vhd_url')"
        local os_sku="$(cat $pi | jq -r '.offer_name')"
        local os_name="$(cat $pi | jq -r '.os_name')"
        local image_version="$(cat $pi | jq -r '.image_version')"
        local image_definition_name="$(cat $pi | jq -r '.sku_name')"
        local image_arch="$(cat $pi | jq -r '.image_architecture')"
        local hyperv_generation="$(cat $pi | jq -r '.hyperv_generation')"
        local log_prefix="[$image_definition_name/$image_version]"

        if [[ "${image_arch,,}" == "arm64" ]]; then
            echo "${log_prefix}: Image Builder does not yet support ARM64 images, skipping ARM64 image: ${image_definition_name}..."
            continue
        fi

        set_unique_vhd_version ${log_prefix} ${vhd_source} || exit $?
        set_sig_config "${os_sku}" "${log_prefix}"

        # if running in ACS test then we need to use a blob copied from AME
        [[ "${DEPLOYENV}" == "test" ]] && vhd_source="https://imagebuilderinputs.blob.core.windows.net/vhds/${unique_vhd_version}.vhd"

        # ensure resources referenced by the image builder template
        id=$(az sig image-definition show -g ${rg_name} -r ${sig_gallery_name} -i ${image_definition_name} | jq -r .id)
        if [ -z "$id" ]; then
            echo "${log_prefix}: SIG image definition ${image_definition_name} not found in gallery ${sig_gallery_name}, skipping this VHD..."
            continue
        else
            echo "${log_prefix}: ${image_definition_name} exists in gallery ${sig_gallery_name} in resource group ${rg_name}"
        fi

        template_name="${image_definition_name}_${unique_vhd_version}"
        template_id=$(az image builder show -g ${IMAGE_BUILDER_RG_NAME} -n ${template_name} | jq -r .id)
        create_template="false"
        
        if [ -z "$template_id" ]; then
            create_template="true"
        else
            template_info=$(az image builder show -g ${IMAGE_BUILDER_RG_NAME} -n ${template_name})
            template_provisioning_state=$(echo "${template_info}" | jq -r .provisioningState)
            if [[ "${template_provisioning_state}" == "Failed" ]]; then
                ensure_new_template ${rg_name} ${template_name} ${log_prefix}
                create_template="true"
            else
                latest_run_provisioning_state=$(echo "${template_info}" | jq -r .lastRunStatus.runState)
                if [[ "${latest_run_provisioning_state}" == "Failed" ]]; then
                    ensure_new_template ${rg_name} ${template_name} ${log_prefix}
                    create_template="true"
                fi
            fi
        fi

        if [[ "${create_template}" == "true" ]]; then
            managed_image_name="ITMI_${image_definition_name}_${unique_vhd_version}"
            ensure_mananged_image ${IMAGE_BUILDER_RG_NAME} ${managed_image_name} ${image_definition_name} ${image_version} ${os_name} ${hyperv_generation} ${vhd_source%%\?*} ${log_prefix} || exit $?

            sed -e "s#<region>#${SIG_REGION}#g" ${IMAGE_BUILDER_TEMPLATE_FILE_NAME} > ${IMAGE_BUILDER_INPUT_FILE_NAME}
            sed -i -e "s#<imageBuilderIdentityUri>#${MSI_OPERATOR_RESOURCE_ID}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
            sed -i -e "s#<managedImageId>#${managed_image_id}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
            sed -i -e "s#<sigSubscriptionId>#${SIG_SUBSCRIPTION_ID}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
            sed -i -e "s#<rgName>#${rg_name}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
            sed -i -e "s#<galleryName>#${sig_gallery_name}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
            sed -i -e "s#<imageDefinitionName>#${image_definition_name}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}
            sed -i -e "s#<imageVersion>#${PREFETCH_IMAGE_VERSION}#g" ${IMAGE_BUILDER_INPUT_FILE_NAME}

            # create the image builder template, this will go and create the staging resource group where image builder will run
            # we create a new staging resource group for each VHD we get from the weekly build pipeline
            echo "${log_prefix}: creating image builder template ${template_name}..."
            az resource create -n ${template_name} \
                --properties @${IMAGE_BUILDER_INPUT_FILE_NAME} --is-full-object \
                --resource-type Microsoft.VirtualMachineImages/imageTemplates \
                --api-version 2022-07-01 \
                --resource-group ${IMAGE_BUILDER_RG_NAME} || exit $?

            echo "${log_prefix}: beginning to run image builder template ${template_name}..."
            az image builder run -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} --no-wait
        else
            echo "${log_prefix}: skipping creation and invocation for template ${template_name}..."
        fi

        template_names+=(${template_name})
    done

    declare -a failed_templates=()
    for template_name in "${template_names[@]}"; do
        echo "waiting for image builder template ${template_name} to finish running..."
        az image builder wait -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} --custom "lastRunStatus.runState!='Running'"

        latest_run_provisioning_state=$(az image builder show -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} | jq -r '.lastRunStatus.runState')
        if [[ "${latest_run_provisioning_state}" != "Succeeded" ]]; then
            echo "${template_name} run failed, last run state: '${latest_run_provisioning_state}'"
            failed_templates+=(${template_name})
            continue
        fi

        prefetch_sig_version_id=$(az image builder show-runs -n ${template_name} -g ${IMAGE_BUILDER_RG_NAME} | jq -r '.[-1].artifactId')
        echo "template ${template_name} finished successfully, output: ${prefetch_sig_version_id}"
    done

    if [ ${#failed_templates[@]} -gt 0 ]; then
        echo "the following image builder templates did not run successfully: ${failed_templates[@]}"
        exit 1
    fi
}

function set_sig_config() {
    if [ $# -ne 2 ]; then
        echo "unexpected number of arguments to set SIG rg name and gallery name"
        exit 1
    fi
    local os_sku=$1
    local log_prefix=$2

    sig_gallery_name="PackerSigGalleryEastUS"
    rg_name="aksvhdtestbuildrg"
    if [[ "${DEPLOYENV}" == "prod" ]]; then
        if [[ "${os_sku}" == "CBLMariner" ]]; then
            sig_gallery_name="AKSCBLMariner"
            rg_name="AKS-CBLMariner"
        else
            sig_gallery_name="AKSUbuntu"
            rg_name="AKS-Ubuntu"
        fi
    fi

    echo "${log_prefix}: set SIG config to ${rg_name}/${sig_gallery_name}"
}

function ensure_new_template() {
    if [ $# -ne 3 ]; then
        echo "unexpected number of arguments to ensure new template"
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
        until [ ! -z "$managed_image_id" ]; do
            echo "${log_prefix}: sleeping for 1m before getting managed image ${rg_name}/${managed_image_name}..."
            sleep 1m
            managed_image_id=$(az image show --resource-group ${rg_name} --name ${managed_image_name} -o json | jq -r ".id")
        done
        echo "${log_prefix}: managed image has been created with uri ${managed_image_id}"
    else
        echo "${log_prefix}: managed image ${managed_image_id} found"
    fi
}

main
