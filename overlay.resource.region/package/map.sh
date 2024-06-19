#!/bin/bash
set -e

echo "Assign msi-acrpull's aks-svc-acr-pull MSI AcrPull role to container registry"

if [ "${CLOUDENV}" == "gb" ] || [ "${CLOUDENV}" == "ff" ] || [ "${CLOUDENV}" == "mc" ]; then
  if [ "${DEPLOYENV}" == "test" ]; then
    echo "${DEPLOYENV} deploy environment in ${CLOUDENV} cloud environment currently not supported"
    exit 0
  fi

  AKS_SVC_MSI_OBJECT_ID=$(az identity show --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" --name \
    "${RESOURCE_NAME_PREFIX}aks-svc-acr-pull" --subscription ${OVERLAY_RESOURCES_SUBSCRIPTION_ID} --query principalId -o tsv 2>/dev/null || echo "")
  ACR_RESOURCE_ID=$(az acr show --resource-group "${ACR_ACSDEPLOYMENT_RESOURCE_GROUP}" --name \
    "${REGISTRY_NAME}" --subscription ${ACR_ACSDEPLOYMENT_SUB_ID} --query id -o tsv 2>/dev/null || echo "")

  if [ "${AKS_SVC_MSI_OBJECT_ID}" == "" ]; then
    echo "${RESOURCE_NAME_PREFIX}aks-svc-acr-pull identity not present in region - ${REGION} in resource group - ${OVERLAY_RESOURCE_GROUP_NAME}"
  elif [ "${ACR_RESOURCE_ID}" == "" ]; then
    echo "${REGISTRY_NAME} acr not present in region - ${REGION} in resource group - ${ACR_ACSDEPLOYMENT_RESOURCE_GROUP}"
  else
    az role assignment create --assignee-object-id ${AKS_SVC_MSI_OBJECT_ID} \
      --role "AcrPull" \
      --scope /subscriptions/${ACR_ACSDEPLOYMENT_SUB_ID}/resourceGroups/${ACR_ACSDEPLOYMENT_RESOURCE_GROUP}/providers/Microsoft.ContainerRegistry/registries/${REGISTRY_NAME}
  fi
else
  echo "${CLOUDENV} cloud environment currently not supported"
fi
