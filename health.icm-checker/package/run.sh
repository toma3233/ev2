#!/bin/bash
set -euo pipefail

base64 -d icm.pfx.raw > icm.pfx

ICM_CHECKER_FLAVOR="${ICM_CHECKER_FLAVOR:-}"

export REGIONS_RESULT_FILE='regions_to_check.txt'
bash parse-regions.sh "${ICM_CHECKER_GROUP_ID}" "${ICM_CHECKER_CUSTOM_REGIONS}" "${ICM_CHECKER_FLAVOR}" "${REGIONS_RESULT_FILE}"
export REGIONS_TO_CHECK=$(cat "${REGIONS_RESULT_FILE}")

bash icm-checker.sh
