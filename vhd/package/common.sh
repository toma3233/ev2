#!/bin/bash
set -x

VHD_URL_REGEX="https:\/\/(.*)?.blob.core.windows.net(:443)?\/vhds\/(.*)?.vhd(.*)?"
BLOB_URL_REGEX="https:\/\/(.*)?.blob.core.windows.net(:443)?\/(.*)?\/(.*)?"

function set_unique_vhd_version() {
    if [ $# -ne 2 ]; then
        echo "unexpected number of arguments to set unique vhd version from vhd_url"
        exit 1
    fi
    local log_prefix=$1
    local vhd_url=$2

    echo "${log_prefix}: attempting to extract unique vhd version from vhd_url: ${vhd_url}..."
    if [[ ! "$vhd_url" =~ $VHD_URL_REGEX ]]; then
      echo "${log_prefix}: unable to extract unique vhd version from vhd_url"
      exit 1
    fi
    
    unique_vhd_version="${BASH_REMATCH[3]}"
}

function set_storage_details_from_vhd_blob_url() {
    if [ $# -ne 2 ]; then
        echo "unexpected number of arguments to set storage account and container names from blob url"
        exit 1
    fi
    local blob_url=$1
    local log_prefix=$2

    echo "${log_prefix}: attempting to extract storage account and container name from blob url..."
    if [[ ! "${blob_url%%\?*}" =~ $BLOB_URL_REGEX ]]; then
      echo "${log_prefix}: unable to extract unique vhd version from vhd_url"
      exit 1
    fi

    storage_account_name="${BASH_REMATCH[1]}"
    storage_container_name="${BASH_REMATCH[3]}"
    vhd_blob_name="${BASH_REMATCH[4]}"
}

function ensure_resource_group() {
  if [ $# -ne 2 ]; then
    echo "unexpected number of arguments to ensure resource group"
    exit 1
  fi
  local sig_region=$1
  local rg_name=$2
  local log_Prefix="[$rg_name/${sig_region}]"
  # Create the necessary infrastructure if it doesn't exist, so that we can publish the SIG image version
  echo "${log_Prefix}: Check if Resource Group exists, if not create it"
  id=$(az group show --name ${rg_name} | jq '.id' )
  if [ -z "$id" ]; then
    echo "${log_Prefix}: Creating resource group ${rg_name}"
    az group create --name ${rg_name} --location ${sig_region} || exit $?
  fi
}

function ensure_storage_resources() {
  if [ $# -ne 5 ]; then
    echo "unexpected number of arguments to ensure storage resources"
    exit 1
  fi
  local sig_region=$1
  local rg_name=$2
  local storage_account=$3
  local storage_container=$4
  local storage_sku=$5
  local log_Prefix="[$rg_name/${storage_account}/${storage_container}/${sig_region}]"

  echo "${local_Prefix}: Checking if storage account ${storage_account} exists, if not create it"
  id=$(az storage account show --name ${storage_account} | jq '.id')
  if [ -z "$id" ]; then
    echo "${log_Prefix}: Creating national cloud HUB VHD storage account ${storage_account}"
    az storage account create -g ${rg_name} --location ${sig_region} -n ${storage_account} --sku ${storage_sku} --kind StorageV2 || exit $?
    
  fi

  echo "${local_Prefix}: Checking if storage container ${storage_container} in storage account ${storage_account} exists, if not create it"
  container_exists=$(az storage container exists --account-name ${storage_account} --name ${storage_container} | jq -r '.exists')
  if [ ${container_exists} != "true" ]; then
    echo "${log_Prefix}: Creating national cloud HUB VHD storage container ${storage_account}/${storage_container}"
    az storage container create --account-name ${storage_account} -n ${storage_container} || exit $?
  fi
}

function ensure_shared_image_gallery() {
  if [ $# -ne 3 ]; then
    echo "unexpected number of arguments to ensure shared image gallery"
    exit 1
  fi
  local sig_region=$1
  local rg_name=$2
  local gallery_name=$3
  local log_Prefix="[$rg_name/$gallery_name/${sig_region}]"
  echo "${log_Prefix}: Check if Shared Image Gallery exists, if not create it"
  id=$(az sig show --resource-group ${rg_name} --gallery-name ${gallery_name})
  if [ -z "$id" ]; then
    echo "${log_Prefix}: Creating Shared Image Gallery ${gallery_name}"
    az sig create --resource-group ${rg_name} --gallery-name ${gallery_name} --location ${SIG_REGION} ${SIG_ADDITIONAL_ARGS} || exit $?
  fi
}

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

# two efforts have been made to handle the image name length limitation that azure image storage only allows an image name of fewer than 80 chars
# 1. remove ${gallery_name} from the image name, which is comparatively constant
# 2. truncate ${SIG_REGION} if the image name overall exceed the name length limit
# the longest raw image name so far comes from windows containerd image for ff int, which is 85
# "MI_usgovvirginia_int_windows-2019-containerd_17763.1911.210507_win-vhd-ev2.0508.3.ev2"
function set_managed_image_name() {
  if [ $# -ne 4 ]; then
    echo "unexpected number of arguments to set managed image name"
    exit 1
  fi
  local sig_region=$1
  local image_definition_name=$2
  local image_version=$3
  local ev2_buildversion=$4
  managed_image_name="MI_${sig_region}_${image_definition_name}_${image_version}_${ev2_buildversion}"
    if [ ${#managed_image_name} -gt 79 ]; then
      toTrim=$(( ${#managed_image_name} - 79 ))
      shortsigregion=${sig_region:0:$(( ${#sig_region} - ${toTrim} ))}
      managed_image_name="MI_${shortsigregion}_${image_definition_name}_${image_version}_${ev2_buildversion}"
    fi
}

