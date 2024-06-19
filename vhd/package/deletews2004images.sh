#!/usr/bin/env bash
set -euo pipefail # fail on...failures
set -x # log commands as they run

[[ -z "${DRY_RUN}" ]] && echo "DRY_RUN is not set" && exit 1
[[ -z "${CLOUDENV}" ]] && echo "CLOUDENV is not set" && exit 1
[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1
[[ -z "${SIG_REGION}" ]] && echo "SIG_REGION is not set" && exit 1
source ./common.sh

echo "Deleting all Windows2004 docker images in ${CLOUDENV}"

echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
az account set --subscription ${SIG_SUBSCRIPTION_ID}

# This is only used to delete the image definition and image versions for Windows2004
# Hardcode the image definition name instead of setting it in a pipeline variable to avoid any mistakes 
image_definition_name="windows-2004"
set_rg_and_sig_from_os_sku "Windows" "${RESOURCE_SUFFIX}" || exit $?

# Exit if the image definition does not exist in the SIG
az sig image-definition show \
  --resource-group ${rg_name} \
  --gallery-name ${gallery_name} \
  --gallery-image-definition ${image_definition_name} > /dev/null || exit 0

# Delete the lock on the image definition
lockName="NoDeleteLock"
lockId="/subscriptions/${SIG_SUBSCRIPTION_ID}/resourceGroups/${rg_name}/providers/Microsoft.Compute/galleries/${gallery_name}/images/${image_definition_name}"
locks=$(az resource lock list --resource ${lockId} | jq length)
# Assume that the lock name must be NoDeleteLock
if [ "$locks" == "0" ]; then
  echo "The image definition ${SIG_SUBSCRIPTION_ID}/${rg_name}/${gallery_name}/${image_definition_name} does not have the lock ${lockName} in ${CLOUDENV}"
else
  if [ "${DRY_RUN}" == "False" ]; then
    echo "Deleting the lock ${lockName} on the image definition ${SIG_SUBSCRIPTION_ID}/${rg_name}/${gallery_name}/${image_definition_name} in ${CLOUDENV}"
    az resource lock delete --name ${lockName} --resource ${lockId}
  else
      echo "DRY-RUN: Showing the lock ${lockName} on the image definition ${SIG_SUBSCRIPTION_ID}/${rg_name}/${gallery_name}/${image_definition_name} in ${CLOUDENV}"
  fi
fi

# first find all published image versions of the particular image definition
# then delete every image version
all_image_versions=($(az sig image-version list \
                        --resource-group ${rg_name} \
                        --gallery-name ${gallery_name} \
                        --gallery-image-definition ${image_definition_name} \
                        | jq -r '.[].name')
                    )

for image_version in "${all_image_versions[@]}"; do
    if [ "${DRY_RUN}" == "False" ]; then
        echo "Deleting Windows2004 docker image ${image_version}"
        az sig image-version delete \
            --resource-group ${rg_name} \
            --gallery-name ${gallery_name} \
            --gallery-image-definition ${image_definition_name} \
            --gallery-image-version ${image_version}
    else
        echo "DRY-RUN: Showing Windows2004 docker image ${image_version}"
        az sig image-version show \
            --resource-group ${rg_name} \
            --gallery-name ${gallery_name} \
            --gallery-image-definition ${image_definition_name} \
            --gallery-image-version ${image_version}
    fi
done

if [ "${DRY_RUN}" == "False" ]; then
    echo "Deleting Windows2004 docker image definition ${image_definition_name}"
    # sleep 120 seconds to avoid that it throws "the nested resource is not deleted". Anyway we can redeploy it since all images should have been deleted
    sleep 120
    az sig image-definition delete \
        --resource-group ${rg_name} \
        --gallery-name ${gallery_name} \
        --gallery-image-definition ${image_definition_name}
else
    echo "DRY-RUN: Showing Windows2004 docker image definition ${image_definition_name}"
    az sig image-definition show \
        --resource-group ${rg_name} \
        --gallery-name ${gallery_name} \
        --gallery-image-definition ${image_definition_name}
fi

if [ "${DRY_RUN}" == "False" ]; then
    echo "Deleted all Windows2004 docker images in ${CLOUDENV}"
else
    echo "DRY-RUN: Listed all Windows2004 docker images in ${CLOUDENV}"
fi