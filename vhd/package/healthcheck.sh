set -ex
[[ -z "${CLOUDENV}" ]] && echo "CLOUDENV is not set" && exit 1
[[ -z "${DEPLOYENV}" ]] && echo "DEPLOYENV is not set" && exit 1
[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1
[[ -z "${GROUP_REPLICA_COUNTS}" ]] && echo "GROUP_REPLICA_COUNTS is not set" && exit 1

source ./common.sh

echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
az account set --subscription ${SIG_SUBSCRIPTION_ID}

function main() {
  
  # Add a publish list specifically for edgezone
  publish_list_edgezone=("1804containerd" "1804gen2containerd" "2204containerd" "2204gen2containerd")
  [[ "${RESOURCE_SUFFIX}" == "EdgeZone" ]] && echo "edge zone publish list for health check is: ${publish_list_edgezone}"

  ubuntu_community_publish_list=("2204containerd" "2204gen2arm64containerd" "2204gen2containerd" "2204gen2TLcontainerd")
  [[ "${RESOURCE_SUFFIX,,}" == "community" ]] && echo "community ubuntu publish list for health check is: ${ubuntu_community_publish_list}"

  for i in publishing-info*/*.json; do
    os_name="$(cat $i | jq -r '.os_name')"
    image_version="$(cat $i | jq -r '.image_version')"
    imagedefinition_name="$(cat $i | jq -r '.sku_name')"
    image_arch="$(cat $i | jq -r '.image_architecture')"
    # os_sku is passed in through offer_name in publishing-info
    os_sku="$(cat $i | jq -r '.offer_name')"
    replication_inverse="$(cat $i | jq -r '.replication_inverse')"

    if [[ "${RESOURCE_SUFFIX}" == "EdgeZone" ]]; then
        # for all image definitions not in the edge zone publish list, skip health check
        if [[ ! " ${publish_list_edgezone[@]} " =~ " ${image_definition_name} " ]]; then
          echo "Skip health check for ${image_definition_name} in the edge zone compute gallery"
          continue
        fi
    fi

    if [ "${RESOURCE_SUFFIX,,}" == "community" ] && [ "${os_sku,,}" == "ubuntu" ]; then
      # Add a publish list, and for all ubuntu image definitions not in the list, skip publishing.
      # We mainly have this so we don't publish VHDs with Ubuntu Pro (e.g. all 1804 + FIPS SKUs) to CIG.
      if [[ ! " ${ubuntu_community_publish_list[*]} " =~ " ${image_definition_name} " ]]; then
        echo "Skip health check for ${image_definition_name} in the community compute gallery"
        continue
      fi
    fi

    set_rg_and_sig_from_os_sku "${os_sku}" "${RESOURCE_SUFFIX}" || exit $?

    if [[ ${image_arch,,} == "arm64" && ${CLOUDENV} != "gb" ]]; then
      # ARM64 Compute is still in Public Preview in Public Cloud, now we can create arm64 image-definition in public cloud only, but cannot in sov clouds
      # so for now we skip publishing arm64 SIG in sov clouds.
      continue
    fi

    if [[ "${imagedefinition_name}" == "2004gen2CVMcontainerd" ]] && [[ "${CLOUDENV}" != "gb" ]]; then
      echo "${imagedefinition_name}: CVM image-definition in sov clouds is not supported now, skip healthcheck CVM sig in sov clouds."
      continue
    fi

    ensure_replication $rg_name $gallery_name $imagedefinition_name $image_version $os_name $replication_inverse
  done
}

function ensure_replication() {
    local rg_name=$1
    local gallery_name=$2
    local imagedefinition_name=$3
    local image_version=$4
    local os_name=$5
    local replication_inverse=$6

    check_replication_targets $rg_name $gallery_name $imagedefinition_name $image_version $os_name $replication_inverse || exit $?
    wait_for_replication $rg_name $gallery_name $imagedefinition_name $image_version $os_name || exit $?
}

function wait_for_replication() {
  local rg_name=$1
  local gallery_name=$2
  local imagedefinition_name=$3
  local image_version=$4
  local os_name=$5

  echo "${imagedefinition_name}: Checking image for replication ${image_version} inside the Gallery ${gallery_name} and Definition ${imagedefinition_name} in RG ${rg_name} for OS:${os_name}"
  while ! az sig image-version show \
    --gallery-image-definition $imagedefinition_name \
    --gallery-image-version $image_version \
    --gallery-name $gallery_name \
    --resource-group $rg_name | grep -q '"provisioningState": "Succeeded"'; do
    echo "${imagedefinition_name}: Still checking for image replication..."
    sleep 60
  done
  echo "${imagedefinition_name}: Replication health check finished"
}

function check_replication_targets() {
  local rg_name=$1
  local gallery_name=$2
  local image_definition_name=$3
  local image_version=$4
  local os_name=$5
  local replication_inverse=$6

  echo "${image_definition_name}: Checking regional replication targets for ${image_version} inside the Gallery ${gallery_name} and Definition ${image_definition_name} in RG ${rg_name} for OS:${os_name}..."

  az sig image-version show -g "$rg_name" -r "$gallery_name" -i "$image_definition_name" -e "$image_version" |
    jq '.publishingProfile.targetRegions[] | "\(.name | gsub(" ";"") | ascii_downcase)=\(.regionalReplicaCount)"' > actual_region_list

  declare -a missing_replications=()
  IFS_backup=$IFS
  IFS=',' read -r -a GROUP_REPLICA_COUNTS_ARR <<< "${GROUP_REPLICA_COUNTS}"
  for rc_pair in ${GROUP_REPLICA_COUNTS_ARR[@]}; do
    echo "raw replication target is $rc_pair for live image ${gallery_name}/${image_definition_name}/${image_version}"
    pair="$rc_pair"
    if [ "${os_name,,}" == "linux" ] && [ "$RESOURCE_SUFFIX" != "EdgeZone" ]; then
      # we don't do any post-processing on the replica counts for EdgeZone
      IFS='=' read -r -a rc_arr <<< "${rc_pair}"
      region=${rc_arr[0]}
      original_replica_count=${rc_arr[1]}
      resolve_replica_count $original_replica_count $replication_inverse || exit $?
      pair="${region}=${replica_count}"
    fi

    echo "resolved replication target is $pair for live image ${gallery_name}/${image_definition_name}/${image_version}"
    if ! grep -q "$pair" actual_region_list; then
      echo "could not find expected replication target $pair for live image: ${gallery_name}/${image_definition_name}/${image_version}"
      missing_replications+=("$pair")
    fi
  done
  IFS=$IFS_backup

  if [ ${#missing_replications[@]} -gt 0 ]; then
      echo "the following replication targets for live image ${gallery_name}/${image_definition_name}/${image_version} are missing: ${missing_replications[*]}"
      exit 1
  fi
}

function resolve_replica_count() {
  local original_replica_count=$1
  local replication_inverse=$2
  if [ "$RESOURCE_SUFFIX" == "community" ]; then
    # CIG image replica counts
    replica_count=$(((original_replica_count + 4) / 5 ))
    return 0
  fi
  if [ "${DEPLOYENV,,}" == "prod" ]; then
    # SIG image replica counts
    replica_count=$((original_replica_count / replication_inverse))
    replica_count=$((replica_count > 5 ? replica_count : 5))
    return 0
  fi
}

main

