#!/usr/bin/env bash
set -euo pipefail # fail on...failures
set -x # log commands as they run

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

# Checking az cli version, should be later than 2.44.0 for supporting SIG at Edge Zones.
echo "Checking az cli version."
az -v

# common variables
IFS=$'\n'
SIG_SUBSCRIPTION_ID="109a5e88-712a-48ae-9078-9ca8b3c81345"
az account set --subscription ${SIG_SUBSCRIPTION_ID}

# Edge Zones list. To remove existing SIG image from a decomm'd Edge Zone, remove it from this list.
# Keep microsoftrrdclab3 and microsoftrrdclab4 here cause those are not decomm'ed yet. But removed in the replication pipeline list bacause of replication failure.
RC_PAIR=(
        westus=microsoftlosangeles1=2
        eastus2euap=microsoftrrdclab3=2
        eastus2euap=microsoftrrdclab4=2
        southcentralus=attdallas1=2
    )

# read the OS name from the VHD publishing info file, the valid OS names: Linux, Windows
VHD_INFO_FILES=(publishing-info-1804-containerd/vhd-publishing-info.json publishing-info-marinerv1/vhd-publishing-info.json)

for VHD_INFO_FILE in "${VHD_INFO_FILES[@]}"; do
    VHD_OS_NAME=""
    VHD_OS_SKU=""
    if [ -s $VHD_INFO_FILE ]; then VHD_OS_NAME="$(cat $VHD_INFO_FILE | jq -r '.os_name')"; fi
    echo "VHD OS name is $VHD_OS_NAME"

    if [ -s $VHD_INFO_FILE ]; then VHD_OS_SKU="$(cat $VHD_INFO_FILE | jq -r '.offer_name')"; fi
    echo "VHD OS SKU name is $VHD_OS_SKU"

    # OS specific variables
    if [ "${VHD_OS_NAME}" == "Linux" ]; then
        if [ "${VHD_OS_SKU}" == "Ubuntu" ]; then
            RG_NAME="AKS-Ubuntu-EdgeZone"
            GALLERY_NAME="AKSUbuntuEdgeZone"        
            IMAGE_DEFINITIONS=(1804containerd 1804fipscontainerd 1804fipsgpucontainerd 1804gen2containerd 1804gen2fipscontainerd 1804gen2fipsgpucontainerd 1804gen2gpucontainerd 1804gpucontainerd 2004gen2cvmcontainerd 2204containerd 2204gen2arm64containerd 2204gen2containerd) # and so on
            # inclusive range [start, end], Ubuntu version examples: 2020.10.08, 2020.10.15
            START_VERSION=$(date -d 'Jan 09 2023' "+%Y.%m.%d")
            FINAL_VERSION=$(date -d 'Jan 11 2023' "+%Y.%m.%d")
        elif [ "${VHD_OS_SKU}" == "CBLMariner" ]; then
            RG_NAME="AKS-CBLMariner-EdgeZone"
            GALLERY_NAME="AKSCBLMarinerEdgeZone"
            IMAGE_DEFINITIONS=(V1 V1GEN2 V2GEN2 V2GEN2ARM64 V2KATAGEN2) # and so on
            # inclusive range [start, end], CBLMariner version examples: 2020.10.08, 2020.10.15
            START_VERSION=$(date -d 'Jan 09 2023' "+%Y.%m.%d")
            FINAL_VERSION=$(date -d 'Jan 11 2023' "+%Y.%m.%d")
        fi
    elif [ "${VHD_OS_NAME}" == "Windows" ]; then
        RG_NAME="AKS-Windows-EdgeZone"
        GALLERY_NAME="AKSWindowsEdgeZone"
        IMAGE_DEFINITIONS=(windows-2019-containerd windows-2022-containerd windows-2022-containerd-gen2)
        # inclusive range [start, end], Windows version examples: 17763.2237.211014, 17763.2300.211110,
        # the latest 6 digits is the version date, examples: 211014, 211110
        START_VERSION=$(date -d 'Jan 09 2023' "+%y%m%d")
        FINAL_VERSION=$(date -d 'Jan 11 2023' "+%y%m%d")
    else
        echo "It can't read the VHD OS name from publishing-info*/*.json. Please check the artifacts."
        exit 1
    fi

    for IMAGE_DEFINITION in "${IMAGE_DEFINITIONS[@]}"; do
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

        echo "Logging all image versions < threshold for $IMAGE_DEFINITION"
        for IMAGE_VERSION in "${IMAGE_VERSIONS[@]}"; do
            echo $IMAGE_VERSION
            az sig image-version show \
                --resource-group ${RG_NAME} \
                --gallery-name ${GALLERY_NAME} \
                --gallery-image-definition $IMAGE_DEFINITION \
                --gallery-image-version $IMAGE_VERSION

            scaling_goal=" --target-edge-zones"

            for rc_pair in "${RC_PAIR[@]}"; do
                scaling_goal+=" ${rc_pair}"
            done

            eval "az sig image-version update \
                --resource-group ${RG_NAME} \
                --gallery-name ${GALLERY_NAME} \
                --gallery-image-definition $IMAGE_DEFINITION \
                --gallery-image-version $IMAGE_VERSION \
                --target-regions eastus=1 \
                $scaling_goal \
                --set safetyProfile.allowDeletionOfReplicatedLocations=true \
                --no-wait" || exit $?

            az sig image-version show \
                --resource-group ${RG_NAME} \
                --gallery-name ${GALLERY_NAME} \
                --gallery-image-definition $IMAGE_DEFINITION \
                --gallery-image-version $IMAGE_VERSION
        done
    done
done

echo "Completed removing the edge zone successfully"
