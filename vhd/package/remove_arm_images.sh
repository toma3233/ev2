#!/bin/bash

 # export SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
 # 
 # RESOURCE_GROUPS=("vhdbuilder") 
 # GALLERIES=("akstestgallery") 
 #
export SUBSCRIPTION=109a5e88-712a-48ae-9078-9ca8b3c81345 
RESOURCE_GROUPS=("AKS-Ubuntu-community" "AKS-CBLMariner-community" "AKS-AzureLinux-community") 
GALLERIES=("AKSUbuntu_community" "AKSCBLMariner_community" "AKSAzureLinux_community") 
az account set --subscription $SUBSCRIPTION

for index in ${!RESOURCE_GROUPS[*]}; do
  RG=${RESOURCE_GROUPS[$index]}
  GALLERY_NAME=${GALLERIES[$index]}
  
  az group list --subscription $SUBSCRIPTION | jq -r '.[] | .name' | grep $RG 
  if [ $? -eq 1 ]; then
      echo "$RG does not exist"
      exit 1
  else
      echo "Processing $RG and $GALLERY_NAME"
      
      image_definitions=$(az sig image-definition list --resource-group "$RG" --gallery-name "$GALLERY_NAME" | jq -r '.[] | .name')
      readarray -t images <<< "$image_definitions"

      resource_namespace="Microsoft.Compute"
      resource_type="galleries/images"

      for image in "${images[@]}"; do
        if [[ ! "$image" =~ arm|Arm|ARM ]]; then
          echo "Skipping non-ARM image definition: $image"
          continue # Skip the rest of the loop for non-ARM images
        fi
        resource_id="/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/$resource_namespace/galleries/$GALLERY_NAME/images/$image"
        locks=$(az lock list --resource $resource_id | jq -r '.[] | .name') 

        if [ -z "$locks" ]; then
          echo "No locks found for Image Definition: $image"
        else
          echo "Locks found for Image Definition: $image. Deleting locks..." 
          for lock in $locks; do
            az lock delete --name "$lock" --resource "$resource_id"
          done
        fi

        az sig image-version list --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $image | jq -r '.[] | .name' | while read -r version ; do
          echo "Deleting image version $version"
          az sig image-version delete --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $image --gallery-image-version $version
        done
        
        echo "Deleting image definition $image"
        az sig image-definition delete --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $image
      done
      
  fi
done
