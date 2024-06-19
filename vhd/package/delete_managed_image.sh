#!/bin/bash
set -x
[[ -z "${CLOUDENV}" ]] && echo "CLOUDENV is not set" && exit 1
[[ -z "${SIG_REGION}" ]] && echo "SIG_REGION is not set" && exit 1
[[ -z "${EV2_BUILDVERSION}" ]] && echo "EV2_BUILDVERSION is not set" && exit 1

source ./common.sh

function main() {
  for i in publishing-info*/*.json; do
    os_name="$(cat $i | jq -r '.os_name')"
    image_version="$(cat $i | jq -r '.image_version')"
    image_definition_name="$(cat $i | jq -r '.sku_name')"
    image_arch="$(cat $i | jq -r '.image_architecture')"
    # os_sku is passed in through offer_name in publishing-info
    os_sku="$(cat $i | jq -r '.offer_name')"
    set_rg_and_sig_from_os_sku "${os_sku}" "${RESOURCE_SUFFIX}" || exit $?

    log_prefix="[$gallery_name/$image_definition_name/$image_version]"

    set_managed_image_name ${SIG_REGION} ${image_definition_name} ${image_version} ${EV2_BUILDVERSION} || exit $?

    if [[ ${image_arch,,} == "arm64" && ${CLOUDENV} != "gb" ]]; then
      continue
    fi
    if [[ "${image_definition_name}" == "2004gen2CVMcontainerd" ]] && [[ "${CLOUDENV}" != "gb" ]]; then
      echo "${image_definition_name}: CVM image-definition in sov clouds is not supported now, skip delete managed image for CVM sig in sov clouds."
      continue
    fi
    echo "${log_prefix}: Deleting managed image ${managed_image_name} from ${rg_name}"
    az image delete --resource-group ${rg_name} --name ${managed_image_name}

  done
}

main
