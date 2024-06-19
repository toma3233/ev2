#!/usr/bin/env bash
set -euo pipefail # fail on...failures
set -x # log commands as they run

root=$(dirname "${BASH_SOURCE[0]}")

[[ -z "${DEPLOYENV}" ]] && echo "DEPLOYENV is not set" && exit 1
[[ -z "${RG_REGION}" ]] && echo "RG_REGION is not set" && exit 1

prefix="nodesig${DEPLOYENV}"
timestamp="$(date -Iseconds | tr -d :+-)"

rg_name="${prefix}-agent-pool"
params="location=${RG_REGION}"

if [[ $# -gt 0 ]] && [[ "$1" == "mariner" ]]; then
  echo "will deploy scaffolding for mariner pool..."
  rg_name="${rg_name}-mariner"
  params="${params} resourceNameSuffix=-mariner"
else
  echo "will deploy scaffolding for ubuntu pool..."
fi

echo "using params: ${params}"
echo "deploying scaffolding resources to resource group ${rg_name}..."

DOTNET_BUNDLE_EXTRACT_BASE_DIR=$(mktemp -d)
export DOTNET_BUNDLE_EXTRACT_BASE_DIR
az group create -l "${RG_REGION}" -n "${rg_name}"
az deployment group create \
  -n deploy-scaffold-${timestamp} \
  -f ${root}/deploy.bicep \
  -g "${rg_name}" \
  --parameters ${params}
