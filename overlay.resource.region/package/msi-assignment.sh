#!/bin/bash
set -euo pipefail

export OVERLAY_RESOURCE_SUBSCRIPTION=${OVERLAY_RESOURCES_SUBSCRIPTION_ID}
# Assign MSI in global resource group to all svc underlay vmss
export OVERLAY_RESOURCE_GROUP="${RESOURCE_NAME_PREFIX_GLOBAL}overlay-global"
export PREFIX=${RESOURCE_NAME_PREFIX_GLOBAL}
export identity_to_remove=""
# To do in the next iteration: 
# 1. remove ignore_nonexistent_msi = true 
# 2. remove || echo
bash common/scripts/assign-msi.sh "$(cat global-msi-assignment.json)" true || echo "assign-msi.sh for global msi fails!"