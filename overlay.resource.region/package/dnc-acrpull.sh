#!/bin/bash
set -e

assignAcnAcrPull() {
  if [ -z "$1" ]; then
    echo "must specify an MSI to use";
    exit 1;
  fi

  if [ "${CLOUDENV}" == "gb" ]; then
    if [ "${DEPLOYENV}" != "prod" ]; then
      echo "${DEPLOYENV} deploy environment in ${CLOUDENV} cloud environment currently not supported"
      exit 0
    fi

    MSI_OBJECT_ID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "$1" --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query principalId -o tsv 2>/dev/null || echo "")

    if [ "${MSI_OBJECT_ID}" == "" ]; then
      echo "$1 identity not present in region - ${REGION} in resource group - ${OVERLAY_RESOURCE_GROUP_NAME}"
    else
      az role assignment create --assignee-object-id ${MSI_OBJECT_ID} \
        --role "AcrPull" \
        --scope "/subscriptions/0895de50-30a3-4b75-aada-5b23ebd4e8bc/resourceGroups/ProductionACR/providers/Microsoft.ContainerRegistry/registries/acnprod"
    fi
  else
    echo "{CLOUDENV} cloud environment currently not supported"
  fi
}

assignAcsProdAcrPull() {
  if [ -z "$1" ]; then
    echo "must specify an MSI to use";
    exit 1;
  fi

  if [ "${CLOUDENV}" == "gb" ]; then
    if [ "${DEPLOYENV}" != "prod" ] && [ "${DEPLOYENV}" != "staging" ]; then
      echo "${DEPLOYENV} deploy environment in ${CLOUDENV} cloud environment currently not supported"
      exit 0
    fi

    MSI_OBJECT_ID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "$1" --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query principalId -o tsv 2>/dev/null || echo "")

    if [ "${MSI_OBJECT_ID}" == "" ]; then
      echo "$1 identity not present in region - ${REGION} in resource group - ${OVERLAY_RESOURCE_GROUP_NAME}"
    else
      az role assignment create --assignee-object-id ${MSI_OBJECT_ID} \
        --role "AcrPull" \
        --scope "/subscriptions/a6cec963-c286-421a-b449-e842b26cee9a/resourceGroups/rp-common/providers/Microsoft.ContainerRegistry/registries/acsproddeployment"
    fi
  else
    echo "{CLOUDENV} cloud environment currently not supported"
  fi
}

assignAcsIntAcrPull() {
  if [ -z "$1" ]; then
    echo "must specify an MSI to use";
    exit 1;
  fi

  if [ "${CLOUDENV}" == "gb" ]; then
    if [ "${DEPLOYENV}" != "int" ] && [ "${DEPLOYENV}" != "intv2" ]; then
      echo "${DEPLOYENV} deploy environment in ${CLOUDENV} cloud environment currently not supported"
      exit 0
    fi

    MSI_OBJECT_ID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
      "$1" --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query principalId -o tsv 2>/dev/null || echo "")

    if [ "${MSI_OBJECT_ID}" == "" ]; then
      echo "$1 identity not present in region - ${REGION} in resource group - ${OVERLAY_RESOURCE_GROUP_NAME}"
    else
      az role assignment create --assignee-object-id ${MSI_OBJECT_ID} \
        --role "AcrPull" \
        --scope "/subscriptions/8c4b4f4e-6bf7-4da8-a51a-d341baf3ce44/resourceGroups/rp-common-intv2/providers/Microsoft.ContainerRegistry/registries/aksdeploymentintv2"
    fi
  else
    echo "{CLOUDENV} cloud environment currently not supported"
  fi
}


echo "Granting ccp-acr-pull MSI the AcrPull role for ACN container registry"
assignAcnAcrPull "${RESOURCE_NAME_PREFIX}ccp-acr-pull"

echo "Granting aks-svc-acr-pull MSI the AcrPull role for ACN container registry"
assignAcnAcrPull "${RESOURCE_NAME_PREFIX}aks-svc-acr-pull"

echo "Granting ccp-acr-pull MSI the AcrPull role for AKS Prod container registry"
assignAcsProdAcrPull "${RESOURCE_NAME_PREFIX}ccp-acr-pull"

echo "Granting stg-ccp-acr-pull MSI the AcrPull role for AKS Prod container registry"
assignAcsProdAcrPull "${RESOURCE_NAME_PREFIX}stg-ccp-acr-pull"

echo "Granting int-ccp-acr-pull MSI the AcrPull role for AKS Intv2 container registry"
assignAcsIntAcrPull "${RESOURCE_NAME_PREFIX}int-ccp-acr-pull"