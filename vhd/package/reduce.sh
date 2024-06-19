#!/usr/bin/env bash
set -euo pipefail # fail on...failures
set -x # log commands as they run

UBUNTU_RG_NAME="AKS-Ubuntu"
UBUNTU_GALLERY_NAME="AKSUbuntu"
UBUNTU_OS_NAME="Linux"
MARINER_RG_NAME="AKS-CBLMariner"
MARINER_GALLERY_NAME="AKSCBLMariner"
MARINER_OS_NAME="Linux"
AZURELINUX_RG_NAME="AKS-AzureLinux"
AZURELINUX_GALLERY_NAME="AKSAzureLinux"
AZURELINUX_OS_NAME="Linux"
WINDOWS_RG_NAME="AKS-Windows"
WINDOWS_GALLERY_NAME="AKSWindows"
WINDOWS_OS_NAME="Windows"
UBUNTU_RG_COMMUNITY="AKS-Ubuntu-community"
UBUNTU_GALLERY_NAME_COMMUNITY="AKSUbuntu_community"
MARINER_RG_COMMUNITY="AKS-CBLMariner-community"
MARINER_GALLERY_NAME_COMMUNITY="AKSCBLMariner_community"
AZURELINUX_RG_COMMUNITY="AKS-AzureLinux-community"
AZURELINUX_GALLERY_NAME_COMMUNITY="AKSAzureLinux_community"
UBUNTU_IMAGE_DEFINITIONS=()
WINDOWS_IMAGE_DEFINITIONS=()
MARINER_IMAGE_DEFINITIONS=()
AZURELINUX_IMAGE_DEFINITIONS=()

START_VERSION_COMMUNITY=$(date -d '3 months ago' "+%Y%m.%d.0")
FINAL_VERSION_COMMUNITY=$(date -d '1 months ago' "+%Y%m.%d.0")


# common variables
IFS=$'\n'
REPLICA_COUNT=1
SIG_SUBSCRIPTION_ID="109a5e88-712a-48ae-9078-9ca8b3c81345"
REGIONS_ARRAY=( $(az account list-locations | jq -r '.[].displayName') )

compareVersions() {
  # return 0 if v1 <= v2
	v1=$1
	v2=$2
    echo "Version to compare v1: ${v1} and v2: ${v2}"
	[[ "${v1}" == "${v2}" ]] && return 0    # if v1 == v2
	smallerVersion=$(echo ${v1} ${v2} | tr ' ' '\n' | sort -V | head -n 1)  # trim space by \n for sort to work, save the first element
	[[ "${v1}" == $smallerVersion ]] && return 0    # if v1 < v2
	return 1
}

find_failed() {
    want=$1
    pidmap=$2
    for word in $pidmap; do
        found=$(echo $word | cut -d= -f1)
        file=$(echo $word | cut -d= -f2)
        if [ "$want" = "$found" ]; then
            cat "$file"
            break
        fi
    done
}

reduce_images() {
  RG_NAME=$1
  GALLERY_NAME=$2
  IMAGE_DEFINITIONS=$3[@]
  START_VERSION=$4
  FINAL_VERSION=$5
  VHD_OS_NAME=$6

  IMAGE_DEFINITIONS_ARRAY=("${!IMAGE_DEFINITIONS}")
  for IMAGE_DEFINITION in "${IMAGE_DEFINITIONS_ARRAY[@]}"; do
      # first find all published image versions of a particular image definition
      # then for every image version, check if it is older than a specified(hardcoded for now) threshold version
      # if yes, store it in the IMAGE_VERSIONS array
      # if no, do nothing, can break in this case too, will discuss and update later
      ALL_IMAGE_VERSIONS=($(az sig image-version list \
                              --resource-group ${RG_NAME} \
                              --gallery-name ${GALLERY_NAME} \
                              --gallery-image-definition $IMAGE_DEFINITION \
                              | jq -r '.[].name')
                          )

      declare -a IMAGE_VERSIONS=()
      for IMAGE_VERSION in "${ALL_IMAGE_VERSIONS[@]}"; do
          CURRENT_VERSION=$IMAGE_VERSION
          if [ "${VHD_OS_NAME}" == "Windows" ]; then
              # Windows image version date is the latest 6 digits: "17763.2237.211014" --> "211014"
              CURRENT_VERSION=${IMAGE_VERSION: -6}
          fi
          if compareVersions $CURRENT_VERSION $FINAL_VERSION; then
              if compareVersions $START_VERSION $CURRENT_VERSION; then
                  IMAGE_VERSIONS+=($IMAGE_VERSION)
              fi
          fi
      done


      pids=""
      pidmap=""
      echo "Logging all image versions < threshold for $IMAGE_DEFINITION"
      for IMAGE_VERSION in "${IMAGE_VERSIONS[@]}"; do
          echo $IMAGE_VERSION
          az sig image-version show \
              --resource-group ${RG_NAME} \
              --gallery-name ${GALLERY_NAME} \
              --gallery-image-definition $IMAGE_DEFINITION \
              --gallery-image-version $IMAGE_VERSION

          az sig image-version show \
              --resource-group ${RG_NAME} \
              --gallery-name ${GALLERY_NAME} \
              --gallery-image-definition $IMAGE_DEFINITION \
              --gallery-image-version $IMAGE_VERSION \
              | jq -r '.publishingProfile.targetRegions[].name' > CURRENT_REGIONS

          TARGET_SET_STRING=""
          for REGION in "${REGIONS_ARRAY[@]}"; do
              EXISTS="false"
              while IFS= read -r CANDIDATE; do
                  if [ "$CANDIDATE" = "$REGION" ]; then
                      EXISTS="true"
                      TARGET_SET_STRING+="--set 'publishingProfile.targetRegions[name=$REGION].regionalReplicaCount=$REPLICA_COUNT' "
                  break
                  fi
              done < CURRENT_REGIONS
              if [ "$EXISTS" = "false" ]; then
                  echo "Skipping region $REGION for $IMAGE_DEFINITION version $IMAGE_VERSION, existing regions: '$(cat CURRENT_REGIONS)'"
              else
                  echo "Scaling region $REGION for $IMAGE_DEFINITION and $IMAGE_VERSION down to $REPLICA_COUNT replicas"
              fi
          done

          logfile="$IMAGE_DEFINITION\_$IMAGE_VERSION.log"

          command="az sig image-version update \
              --resource-group ${RG_NAME} \
              --gallery-name ${GALLERY_NAME} \
              --gallery-image-definition $IMAGE_DEFINITION \
              --gallery-image-version $IMAGE_VERSION \
              $TARGET_SET_STRING"

          eval "$command" > "$logfile" 2>&1 &

          pid=$!
          pids="$pids $pid"
          pidmap="$pidmap $pid=$logfile"

          az sig image-version show \
              --resource-group ${RG_NAME} \
              --gallery-name ${GALLERY_NAME} \
              --gallery-image-definition $IMAGE_DEFINITION \
              --gallery-image-version $IMAGE_VERSION
      done
      for pid in $pids; do
          wait $pid || find_failed $pid $pidmap
      done
  done

  echo "Completed all regions successfully"
}

az account set --subscription ${SIG_SUBSCRIPTION_ID}

for pi in publishing-info*/*.json; do
  os_name="$(cat $pi | jq -r '.os_name')"
  image_definition_name="$(cat $pi | jq -r '.sku_name')"
  offer_name="$(cat $pi | jq -r '.offer_name')"

  if [ "${os_name}" == "Windows" ]; then
    WINDOWS_IMAGE_DEFINITIONS+=("${image_definition_name}")
  else
    if [ "${offer_name}" == "Ubuntu" ]; then
      UBUNTU_IMAGE_DEFINITIONS+=("${image_definition_name}")
    elif [ "${offer_name}" == "CBLMariner" ]; then
      MARINER_IMAGE_DEFINITIONS+=("${image_definition_name}")
    elif [ "${offer_name}" == "AzureLinux" ]; then
      AZURELINUX_IMAGE_DEFINITIONS+=("${image_definition_name}")
    else
      echo "invalid offer name"
      exit 1
    fi
  fi
done

if [ ${#WINDOWS_IMAGE_DEFINITIONS[@]} -eq 0 ]; then
  echo "publishing info does not contain any windows images"
else
  # inclusive range [start, end], Windows version examples: 17763.2237.211014, 17763.2300.211110,
  # the latest 6 digits is the version date, examples: 211014, 211110
  START_VERSION=$(date -d '8 months ago' "+%y%m%d")
  FINAL_VERSION=$(date -d '6 months ago' "+%y%m%d")
  reduce_images ${WINDOWS_RG_NAME} ${WINDOWS_GALLERY_NAME} WINDOWS_IMAGE_DEFINITIONS ${START_VERSION} ${FINAL_VERSION} ${WINDOWS_OS_NAME}
fi

if [ ${#UBUNTU_IMAGE_DEFINITIONS[@]} -eq 0 ]; then
  echo "publishing info does not contain any ubuntu images"
else
  # inclusive range [start, end], Ubuntu version examples: 2020.10.08, 2020.10.15
  # Since March 6th 2023, the VHD version has changed to : 202303.06.0, 202303.13.0, i.e in the format YYYYMM.DD.0
  # The last VHD with the original format was 2023.02.15, and as of the date of this commit, START_VERSION = 2023.02.16
  # Therefore, we are now going to move to VHDs with the newer format and hence need to update the script
  START_VERSION=$(date -d '7 months ago' "+%Y%m.%d.0")
  FINAL_VERSION=$(date -d '6 months ago' "+%Y%m.%d.0")
  reduce_images ${UBUNTU_RG_NAME} ${UBUNTU_GALLERY_NAME} UBUNTU_IMAGE_DEFINITIONS ${START_VERSION} ${FINAL_VERSION} ${UBUNTU_OS_NAME}
  reduce_images ${UBUNTU_RG_COMMUNITY} ${UBUNTU_GALLERY_NAME_COMMUNITY} UBUNTU_IMAGE_DEFINITIONS ${START_VERSION_COMMUNITY} ${FINAL_VERSION_COMMUNITY} ${UBUNTU_OS_NAME}
fi

if [ ${#MARINER_IMAGE_DEFINITIONS[@]} -eq 0 ]; then
  echo "publishing info does not contain any mariner images"
else
  # inclusive range [start, end], Ubuntu version examples: 2020.10.08, 2020.10.15
  # Since March 6th 2023, the VHD version has changed to : 202303.06.0, 202303.13.0, i.e in the format YYYYMM.DD.0
  # The last VHD with the original format was 2023.02.15, and as of the date of this commit, START_VERSION = 2023.02.16
  # Therefore, we are now going to move to VHDs with the newer format and hence need to update the script
  START_VERSION=$(date -d '7 months ago' "+%Y%m.%d.0")
  FINAL_VERSION=$(date -d '6 months ago' "+%Y%m.%d.0")
  reduce_images ${MARINER_RG_NAME} ${MARINER_GALLERY_NAME} MARINER_IMAGE_DEFINITIONS ${START_VERSION} ${FINAL_VERSION} ${MARINER_OS_NAME}
  reduce_images ${MARINER_RG_COMMUNITY} ${MARINER_GALLERY_NAME_COMMUNITY} MARINER_IMAGE_DEFINITIONS ${START_VERSION_COMMUNITY} ${FINAL_VERSION_COMMUNITY} ${MARINER_OS_NAME}
fi

if [ ${#AZURELINUX_IMAGE_DEFINITIONS[@]} -eq 0 ]; then
  echo "publishing info does not contain any azure linux images"
else
  # inclusive range [start, end], Ubuntu version examples: 2020.10.08, 2020.10.15
  # Since March 6th 2023, the VHD version has changed to : 202303.06.0, 202303.13.0, i.e in the format YYYYMM.DD.0
  # The last VHD with the original format was 2023.02.15, and as of the date of this commit, START_VERSION = 2023.02.16
  # Therefore, we are now going to move to VHDs with the newer format and hence need to update the script
  START_VERSION=$(date -d '7 months ago' "+%Y%m.%d.0")
  FINAL_VERSION=$(date -d '6 months ago' "+%Y%m.%d.0")
  reduce_images ${AZURELINUX_RG_NAME} ${AZURELINUX_GALLERY_NAME} AZURELINUX_IMAGE_DEFINITIONS ${START_VERSION} ${FINAL_VERSION} ${AZURELINUX_OS_NAME}
  reduce_images ${AZURELINUX_RG_COMMUNITY} ${AZURELINUX_GALLERY_NAME_COMMUNITY} AZURELINUX_IMAGE_DEFINITIONS ${START_VERSION_COMMUNITY} ${FINAL_VERSION_COMMUNITY} ${AZURELINUX_OS_NAME}
fi
