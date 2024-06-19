#!/bin/bash

export SUBSCRIPTION=109a5e88-712a-48ae-9078-9ca8b3c81345
RG="AKS-AzureLinux"
GALLERY_NAME="AKSAzureLinux"
IMAGE_DEFINITION="V2gen2arm64"
az account set --subscription $SUBSCRIPTION

az group list --subscription $SUBSCRIPTION | jq -r '.[] | .name' | grep $RG
if [ $? -eq 1 ]; then
  echo "$RG does not exist"
  exit 1
else
  echo "Processing $RG and $GALLERY_NAME and $IMAGE_DEFINITION"
  resource_namespace="Microsoft.Compute"
  resource_type="galleries/images"
  resource_id="/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/$resource_namespace/galleries/$GALLERY_NAME/images/$IMAGE_DEFINITION"

  locks=$(az lock list --resource $resource_id | jq -r '.[] | .name')
  if [ -z "$locks" ]; then
    echo "No locks found for Image Definition: $IMAGE_DEFINITION"
  else
    echo "Locks found for Image Definition: $IMAGE_DEFINITION. Deleting locks..."
    for lock in $locks; do
      az lock delete --name "$lock" --resource "$resource_id"
    done
  fi

  az sig image-version list --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $IMAGE_DEFINITION | jq -r '.[] | .name' | while read -r version ; do
    echo "Deleting image version $version"
    az sig image-version delete --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $IMAGE_DEFINITION --gallery-image-version $version
  done

  echo "Deleting image definition $IMAGE_DEFINITION"
  az sig image-definition delete --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $IMAGE_DEFINITION
fi
