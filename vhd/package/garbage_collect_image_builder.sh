#!/bin/bash
set -ex

# We exit with this particular exit code in the case where the script was in danger of deleting protected resource groups
ERR_DANGEROUS_DELETE_ATTEMPTED=66

[[ -z "${SIG_SUBSCRIPTION_ID}" ]] && echo "SIG_SUBSCRIPTION_ID is not set" && exit 1

function main() {
  [ $# -ne 2 ] && echo "garbage_collect_image_builder.sh requires exactly 2 arguments to be specified" && exit 1
  local tags=$1
  local run_type=$2

  echo "az account set --subscription ${SIG_SUBSCRIPTION_ID}"
  az account set --subscription ${SIG_SUBSCRIPTION_ID}

  local image_builder_rgs
  if [ "$tags" == "tags" ]; then
    echo "looking for resource groups to garbage collect that have been explicitly tagged for prefetch optimization"
    image_builder_rgs="$(az group list | jq -r '.[] | select(.name | test("AKS-Image-Builder-*")) | select(.tags.SIGReleaseStep == "PrefetchOptimization") | select(.properties.provisioningState == "Succeeded" or .properties.provisioningState == "Failed").name')"
  elif [ "$tags" == "notags" ]; then
    echo "looking for resource groups to garbage collect without any tags"
    # we need to explicitly filter on null tags otherwise this will return the set of staging resource groups as well
    image_builder_rgs="$(az group list | jq -r '.[] | select(.name | test("AKS-Image-Builder-*")) | select(.tags == null) | select(.properties.provisioningState == "Succeeded" or .properties.provisioningState == "Failed").name')"
  else
    echo "garbage_collect_image_builder.sh: unrecognized tags directive, should be 'tags' or 'notags'"
    exit 1
  fi

  echo "will attempt to garbage collect resource groups: $image_builder_rgs"

  if [ -n "$image_builder_rgs" ]; then
    for rg in $image_builder_rgs; do
      if [ "$rg" == "AKS-Ubuntu" ] || [ "$rg" == "AKS-CBLMariner" ] || [ "$rg" == "AKS-AzureLinux" ] || [ "$rg" == "AKS-Ubuntu-EdgeZone" ] || [ "$rg" == "AKS-Windows" ] || [[ "$rg" =~ AKS-.*-community ]]; then
        echo "attempted to delete dangerous RG: $rg, exiting hard..."
        exit $ERR_DANGEROUS_DELETE_ATTEMPTED
      fi

      echo "garbage collecting image builder RG $rg..."
      if [ "${run_type,,}" == "dryrun" ]; then
        echo "this is a dry run, skipping delete operation on resource group: $rg"
        continue
      fi

      az group delete -g "$rg" -y --no-wait || exit $?
      echo "initiated delete operation on resource group: $rg"
    done

    if [ "${run_type,,}" != "dryrun" ]; then
      for rg in $image_builder_rgs; do
        wait_for_rg_deletion "$rg" || exit $?
        echo "resource group $rg has been deleted"
      done
    fi
  else
    echo "no image builder resource groups found to garbage collect"
  fi
}

function wait_for_rg_deletion() {
  [ $# -ne 1 ] && echo "wait_for_rg_deletion expects exactly 1 argument" && exit 1
  local rg=$1

  provisioning_state=$(az group show -g "$rg" | jq -r '.properties.provisioningState')
  until [ -z "$provisioning_state" ]; do
    echo "sleeping for 30 seconds while waiting for deletion of resource group: $rg, currently in provisioning state: $provisioning_state"
    sleep 30
    provisioning_state=$(az group show -g "$rg" | jq -r '.properties.provisioningState')
  done
}

main "$@"