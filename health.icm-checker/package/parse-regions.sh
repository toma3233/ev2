#!/bin/bash
set -euo pipefail
CURRENT_GROUP_ID=$1
CUSTOM_REGIONS=$2
FLAVOR=$3
RESULT_FILE=$4

echo "CURRENT_GROUP_ID:'${CURRENT_GROUP_ID}',CUSTOM_REGIONS:'${CUSTOM_REGIONS}',FLAVOR:'${FLAVOR}'"
RESULT_REGIONS="$CUSTOM_REGIONS"

SUFFIX=''
if [[ ! -z "${FLAVOR}" ]]; then
    SUFFIX="-${FLAVOR}"
fi

if [[ -z "$RESULT_REGIONS" ]]; then
    FULL_GROUP_NAME="${CLOUDENV}.${DEPLOYENV}.${CURRENT_GROUP_ID}"
    echo "FULL_GROUP_NAME:${FULL_GROUP_NAME}"
    CHECK_GROUP=$(perl ./parse-suite.pl "current_to_check.suite${SUFFIX}.yaml" "${FULL_GROUP_NAME}")
    echo "CHECK_GROUP:${CHECK_GROUP}"
    if [[ ! -z "${CHECK_GROUP}" ]]; then
        RESULT_REGIONS=$(perl ./parse-suite.pl "group_to_region.suite${SUFFIX}.yaml" "${CHECK_GROUP}")
    fi
fi

FORMATTED_RESULT_REGIONS=$(echo "${RESULT_REGIONS}," | perl -p -e 's/(.*?),/^$1\$\|/g;chomp;chop;')
echo "FORMATTED_RESULT_REGIONS:${FORMATTED_RESULT_REGIONS}"

echo "${FORMATTED_RESULT_REGIONS}" > "${RESULT_FILE}"
