#!/usr/bin/env bash
set -euo pipefail # fail on...failures
set -x # log commands as they run

root=$(dirname "${BASH_SOURCE[0]}")

[[ -z "${DEPLOYENV}" ]] && echo "DEPLOYENV is not set" && exit 1
[[ -z "${RG_REGION}" ]] && echo "RG_REGION is not set" && exit 1

prefix="nodesig${DEPLOYENV}"
timestamp="$(date -Iseconds | tr -d :+-)"

rg_name="${prefix}-agent-pool"
delegate_params="env=${DEPLOYENV}"
pool_params="env=${DEPLOYENV} location=${RG_REGION}"

if [[ $# -gt 0 ]] && [[ "$1" == "mariner" ]]; then
  echo "will deploy mariner delegation & pool resources..."
  rg_name="${rg_name}-mariner"
  delegate_params="${delegate_params} resourceNameSuffix=-mariner"
  pool_params="${pool_params} resourceNameSuffix=-mariner"
else
  echo "will deploy ubuntu delegation & pool resources..."
fi

echo "using delegate params: ${delegate_params}"
echo "using pool params: ${pool_params}"
echo "deploying delegation resources to subscription & pool resources to resource group ${rg_name}..."

DOTNET_BUNDLE_EXTRACT_BASE_DIR=$(mktemp -d)
export DOTNET_BUNDLE_EXTRACT_BASE_DIR
az group create -l "${RG_REGION}" -n "${rg_name}"
az deployment sub create \
  -n deploy-delegate-${timestamp} \
  -f ${root}/modules/delegate.bicep \
  -l ${RG_REGION} \
  --parameters ${delegate_params}

az deployment group create \
  -n deploy-pool-${timestamp} \
  -f ${root}/deploy.bicep \
  -g "${rg_name}" \
  --parameters ${pool_params}
