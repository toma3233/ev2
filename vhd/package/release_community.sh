#!/bin/bash
set -x

[[ -z "${CLOUDENV}" ]] && echo "CLOUDENV is not set" && exit 1
[[ -z "${DEPLOYENV}" ]] && echo "DEPLOYENV is not set" && exit 1
[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1
[[ -z "${SIG_REGION}" ]] && echo "SIG_REGION is not set" && exit 1
[[ -z "${GROUP_REPLICA_COUNTS}" ]] && echo "GROUP_REPLICA_COUNTS is not set" && exit 1
[[ -z "${EV2_BUILDVERSION}" ]] && echo "EV2_BUILDVERSION is not set" && exit 1
if [ ${CLOUDENV} == "ex" ] || [ ${CLOUDENV} == "rx" ] || [ ${CLOUDENV} == 'mc' ] || [ ${CLOUDENV} == 'ff' ]; then
  [[ -z "${SOV_CLOUD_HUB_STORAGE_ACCOUNT}" ]] && echo "SOV_CLOUD_HUB_STORAGE_ACCOUNT is not set" && exit 1
  [[ -z "${SOV_CLOUD_HUB_CONTAINER}" ]] && echo "SOV_CLOUD_HUB_CONTAINER is not set" && exit 1
fi
source ./common.sh

function main() {
  echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
  az account set --subscription ${SIG_SUBSCRIPTION_ID}

  RESOURCE_SUFFIX="community"

  # Add a publish list, and for all ubuntu image definitions not in the list, skip publishing.
  # We mainly have this so we don't publish VHDs with Ubuntu Pro (e.g. all 1804 + FIPS SKUs) to CIG.
  ubuntu_community_publish_list=("2204containerd" "2204gen2arm64containerd" "2204gen2containerd" "2204gen2TLcontainerd")

  for i in publishing-info*/*.json; do
    local os_name="$(cat $i | jq -r '.os_name')"
    local image_version="$(cat $i | jq -r '.image_version')"
    local image_definition_name="$(cat $i | jq -r '.sku_name')"
    local image_arch="$(cat $i | jq -r '.image_architecture')"
    # os_sku is passed in through offer_name in publishing-info
    local os_sku="$(cat $i | jq -r '.offer_name')"

    if [ "${os_sku,,}" == "ubuntu" ]; then
      if [[ ! " ${ubuntu_community_publish_list[*]} " =~ " ${image_definition_name} " ]]; then
        echo "Skip publishing ${image_definition_name} in the community compute gallery"
        continue
      fi
    fi
    
    set_rg_and_sig_from_os_sku "${os_sku}" "${RESOURCE_SUFFIX}" || exit $?

    # ensure ResourceGroup and Gallery
    ensure_resource_group ${SIG_REGION} ${rg_name} || exit $?
    
    local gallery_prefix="AKS${os_sku}"
    SIG_ADDITIONAL_ARGS="--permissions community --publisher-uri https://www.microsoft.com/ --publisher-email aks@microsoft.com --eula https://azure.microsoft.com/en-us/support/legal/ --public-name-prefix ${gallery_prefix}"
    ensure_shared_image_gallery ${SIG_REGION} ${rg_name} ${gallery_name} || exit $?
    # make it available to users
    # once in use, images can not be deleted (not that we ever delete them anyway)
    az sig share enable-community --resource-group ${rg_name} --gallery-name ${gallery_name} || exit $?

    local vhd_source="$(cat $i | jq -r '.vhd_url')"
    local hyperv_generation="$(cat $i | jq -r '.hyperv_generation')"
    local log_prefix="[$gallery_name/$image_definition_name/$image_version]"

    if [[ ${image_arch,,} == "arm64" && ${CLOUDENV} != "gb" ]]; then
      # ARM64 Compute is still in Public Preview in Public Cloud, now we can create arm64 image-definition in public cloud only, but cannot in sov clouds
      # so for now we skip publishing arm64 SIG in sov clouds.
      echo "${log_prefix}: creating arm64 image-definition in sov clouds is not supported now, skip publishing arm64 sig in sov clouds."
      continue
    fi

    #ensure image definition
    echo "${log_prefix}: check image definition existence"
    id=$(az sig image-definition show \
      --resource-group ${rg_name} \
      --gallery-name ${gallery_name} \
      --gallery-image-definition ${image_definition_name} | jq .id)
    if [ -z "$id" ]; then
      echo "${log_prefix}: image definition not found, creating..."

      TARGET_FEATURE_STRING=""
      if [[ "${image_definition_name}" == "2004gen2CVMcontainerd" ]]; then
        if [[ "${CLOUDENV}" != "gb" ]]; then
          echo "${log_prefix}: creating CVM image-definition in sov clouds is not supported now, skip publishing CVM sig in sov clouds."
          continue
        fi
        echo "${log_prefix}: creating image definition for CVM 2004 with securityType=CVMS"
        TARGET_FEATURE_STRING+="--features SecurityType=ConfidentialVMSupported"
      fi

      # TL skus supported: Ubuntu 22.04, MarinerV2, MarinerV2 Kata
      if [[ "${image_definition_name}" == *"TL"* ]]; then
        echo "${log_prefix}: creating image definition for ${image_definition_name} with securityType=TL"
        TARGET_FEATURE_STRING+="--features SecurityType=TrustedLaunch"
      fi

      if [[ ${image_arch,,} == "arm64" ]]; then
        az sig image-definition create \
          --resource-group ${rg_name} \
          --gallery-name ${gallery_name} \
          --gallery-image-definition ${image_definition_name} \
          --publisher microsoft-aks \
          --offer ${gallery_name} \
          --sku ${image_definition_name} \
          --os-type ${os_name} \
          --architecture Arm64 \
          --location ${SIG_REGION} \
          --hyper-v-generation ${hyperv_generation} \
          $TARGET_FEATURE_STRING || exit $?
      else
        az sig image-definition create \
          --resource-group ${rg_name} \
          --gallery-name ${gallery_name} \
          --gallery-image-definition ${image_definition_name} \
          --publisher microsoft-aks \
          --offer ${gallery_name} \
          --sku ${image_definition_name} \
          --os-type ${os_name} \
          --location ${SIG_REGION} \
          --hyper-v-generation ${hyperv_generation} \
          $TARGET_FEATURE_STRING || exit $?
      fi

      id="$(az sig image-definition show \
      --resource-group ${rg_name} \
      --gallery-name ${gallery_name} \
      --gallery-image-definition ${image_definition_name} | jq .id)"
      eval "az resource lock create --lock-type CanNotDelete -n NoDeleteLock --resource $id"
    else
      echo "${log_prefix}: image definition found, skip creating."
    fi

    create_or_scale_image_version $log_prefix ${rg_name} ${gallery_name} $image_definition_name $image_version $os_name $vhd_source $hyperv_generation
  done
}

function create_or_scale_image_version() {
  local log_prefix=$1
  local rg_name=$2
  local gallery_name=$3
  local image_definition_name=$4
  local image_version=$5

  echo "${log_prefix}: check image version existence"
  id=$(az sig image-version show \
    --resource-group ${rg_name} \
    --gallery-name ${gallery_name} \
    --gallery-image-definition ${image_definition_name} \
    --gallery-image-version ${image_version} | grep "provisioningState")

  if [ -z "$id" ]; then
    echo "${log_prefix}: image version not found, creating..."
    create_image_version "$@"
  fi

  echo "${log_prefix}: image version found, scaling..."
  scale_image_version "$@"
}

function create_image_version() {
  local log_prefix=$1
  local rg_name=$2
  local gallery_name=$3
  local image_definition_name=$4
  local image_version=$5
  local os_name=$6
  local vhd_source=$7
  local hyperv_generation=$8

  # ensure managed image
  set_managed_image_name ${SIG_REGION} ${image_definition_name} ${image_version} ${EV2_BUILDVERSION} || exit $?
  echo "${log_prefix}: check managed image existence: ${rg_name}/${managed_image_name}"
  managed_image_uri=$(az image show --resource-group ${rg_name} --name ${managed_image_name} -o json | jq -r ".id")
  if [ -z "$managed_image_uri" ]; then
    echo "${log_prefix}: managed image ${rg_name}/${managed_image_name} not found, creating..."
    echo "$log_prefix: public cloud vhd_source is ${vhd_source}"
    if [ ${CLOUDENV} == 'mc' ] || [ ${CLOUDENV} == 'ff' ]; then
      blob_name="${gallery_name}_${image_definition_name}_${image_version}.vhd"
      if [ ${CLOUDENV} == 'ff' ]; then
        STORAGE_DOMAIN="blob.core.usgovcloudapi.net"
      else
        STORAGE_DOMAIN="blob.core.chinacloudapi.cn"
      fi
      copyStatus=$(az storage blob show \
          --name ${blob_name} \
          --container-name ${SOV_CLOUD_HUB_CONTAINER} \
          --account-name ${SOV_CLOUD_HUB_STORAGE_ACCOUNT} \
          --subscription ${SIG_SUBSCRIPTION_ID} 2>/dev/null | jq -r '.properties.copy.status')

      if [ "${copyStatus}" != "success" ]; then
        echo "$log_prefix: blob ${blob_name} in storage account: ${SOV_CLOUD_HUB_STORAGE_ACCOUNT}, container: ${SOV_CLOUD_HUB_CONTAINER} has not yet been copied successfully (status = ${copyStatus}) "
        exit 1
      fi

      vhd_source="https://${SOV_CLOUD_HUB_STORAGE_ACCOUNT}.${STORAGE_DOMAIN}/${SOV_CLOUD_HUB_CONTAINER}/${blob_name}"

    elif [ ${CLOUDENV} == "ex" ] || [ ${CLOUDENV} == "rx" ]; then
      vhd_source_without_query_parameter=$(echo ${vhd_source%%\?*})
      blob_name=$(echo ${vhd_source_without_query_parameter##*/} | sed 's/?.*//')
      echo "$log_prefix: blob_name is: ${blob_name}"
      vhd_source="https://${SOV_CLOUD_HUB_STORAGE_ACCOUNT}.blob.${STORAGE_SUFFIX}/${SOV_CLOUD_HUB_CONTAINER}/${blob_name}"
    fi

    eval "az image create --resource-group ${rg_name} --name ${managed_image_name} --os-type ${os_name} --hyper-v-generation ${hyperv_generation} --source ${vhd_source}" || exit $?
    until [ ! -z "$managed_image_uri" ]; do
      echo "${log_prefix}: sleeping for 1m before getting managed image ${rg_name}/${managed_image_name}..."
      sleep 1m
      managed_image_uri=$(az image show --resource-group ${rg_name} --name ${managed_image_name} -o json | jq -r ".id")
    done
  fi
  echo "${log_prefix}: managed image ${managed_image_uri} found"

  #create image version
  echo "${log_prefix}: creating image version..."
  az sig image-version create \
    --resource-group ${rg_name} \
    --gallery-name ${gallery_name} \
    --gallery-image-definition ${image_definition_name} \
    --gallery-image-version ${image_version} \
    --managed-image "${managed_image_uri}" \
    --storage-account-type ${STORAGE_ACCOUNT_TYPE} \
    --no-wait || exit $?

  local image_version_state=""
  until [ ! -z "$image_version_state" ]; do
    echo "${log_prefix}: sleeping for 30s before checking image version existence..."
    sleep 30s
    image_version_state=$(az sig image-version show \
      --resource-group ${rg_name} \
      --gallery-name ${gallery_name} \
      --gallery-image-definition ${image_definition_name} \
      --gallery-image-version ${image_version} | grep "provisioningState")
  done
  echo "${log_prefix}: image version ${image_version_state}"
}

function scale_image_version() {
  local log_prefix=$1
  local rg_name=$2
  local gallery_name=$3
  local image_definition_name=$4
  local image_version=$5

  az sig image-version show -g $rg_name -r $gallery_name -i $image_definition_name -e $image_version \
    | jq .publishingProfile.targetRegions | jq .[].name \
    | awk '{print "\"name\"=" $0; (gsub(/^[ \t]+|[ \t]+$|\"| /, "", $0)); print "shortname=" tolower($0) }' > curSIG_${image_definition_name}_${image_version}

  if [ ${CLOUDENV} == "ex" ] || [ ${CLOUDENV} == "rx" ]; then
    # Due to LX cloud CLI version mismatch, we have to use --target-regions instead of publishingProfile.targetRegions
    # to set replica count. We can remove this workaround later after CLI is udpated in LX cloud.
    scaling_goal=" --target-regions "
    IFS=',' read -r -a GROUP_REPLICA_COUNTS_ARR <<< "${GROUP_REPLICA_COUNTS}"
    for rc_pair in ${GROUP_REPLICA_COUNTS_ARR[@]}; do
      IFS='=' read -r -a rc_arr <<< "${rc_pair}"
      region=${rc_arr[0]}
      replica_count=${rc_arr[1]}
      scaling_goal+=" ${region}=${replica_count}"
    done
  else
    #GROUP_REPLICA_COUNTS in the format of: regionA=10,regionB=20
    scaling_goal=""
    IFS=',' read -r -a GROUP_REPLICA_COUNTS_ARR <<< "${GROUP_REPLICA_COUNTS}"
    for rc_pair in ${GROUP_REPLICA_COUNTS_ARR[@]}; do
      IFS='=' read -r -a rc_arr <<< "${rc_pair}"
      region=${rc_arr[0]}
      original_replica_count=${rc_arr[1]}
      # In Bash, when you use the $(( )) arithmetic expansion with division, it automatically floors the result to the nearest whole number. This is because Bash does not support floating-point arithmetic natively, and any decimal part is truncated. To Round up, we take the divsor - 1 + count / divisor to round up
      replica_count=$(((original_replica_count + 4) / 5 ))
      # TODO: skip if region is in skipping list
      region_selector=`cat curSIG_${image_definition_name}_${image_version} | grep -e "^shortname=${region}$" -B 1 | grep "\"name\"=\""`
      if [ -z "$region_selector" ]; then
        scaling_goal+=" --add publishingProfile.targetRegions name=${region} regionalReplicaCount=${replica_count}"
      else
        scaling_goal+=" --set publishingProfile.targetRegions[$region_selector].regionalReplicaCount=${replica_count}"
      fi
    done
  fi

  eval "az sig image-version update \
    --resource-group ${rg_name} \
    --gallery-name ${gallery_name} \
    --gallery-image-definition ${image_definition_name} \
    --gallery-image-version ${image_version} \
    $scaling_goal \
    --no-wait" || exit $?
}

function wait_blob_copy() {
  log_prefix=$1
  account_name=$2
  container_name=$3
  blob_name=$4
  while ! az storage blob show \
    --name ${blob_name} \
    --container-name ${container_name} \
    --account-name ${account_name} \
    --subscription ${SIG_SUBSCRIPTION_ID} 2>&1 | grep -q '"status": "success"'; do
    echo "${log_prefix}: Waiting for copy to storage account: ${account_name}, container: ${container_name}, blob ${blob_name}"
    sleep 120
  done
  echo "${log_prefix}: Copy done for storage account: ${account_name}, container: ${container_name}, blob ${blob_name}"
}

main

