#!/bin/bash
export SUBSCRIPTION=109a5e88-712a-48ae-9078-9ca8b3c81345 

# Put your list of operating systems here
OS_LIST=("Ubuntu" "CBLMariner" "Windows")
# UBUNTU Image Example from sig gallery, community gallery will have the suffix Community
# 	"id": "/subscriptions/109a5e88-712a-48ae-9078-9ca8b3c81345/resourceGroups/AKS-Ubuntu/providers/Microsoft.Compute/galleries/AKSUbuntu/images/2204gen2containerd/versions/202309.06.0"
# Mariner 
# 	"id": "/subscriptions/109a5e88-712a-48ae-9078-9ca8b3c81345/resourceGroups/AKS-CBLMariner/providers/Microsoft.Compute/galleries/AKSCBLMariner/images/V1/versions/202308.22.0"
# Windows 
# 	"id": "/subscriptions/109a5e88-712a-48ae-9078-9ca8b3c81345/resourceGroups/AKS-Windows/providers/Microsoft.Compute/galleries/AKSWindows/images/windows-2019-containerd/versions/17763.4645.230712"

az account set --subscription $SUBSCRIPTION

for OS in "${OS_LIST[@]}"; do
    # Construct the resource group and gallery name based on the OS
    RG="AKS-$OS-community"
    GALLERY_NAME="AKS${OS}_community"
    
    az group list --subscription $SUBSCRIPTION | jq -r '.[] | .name' | grep -q $RG 
    if [ $? -eq 1 ]; then
        echo "$RG does not exist"
        continue
    fi
    az sig list --subscription $SUBSCRIPTION | jq -r '.[] | .name' | grep $GALLERY_NAME 
    if [ $? -eq 1 ]; then
        echo "$GALLERY_NAME does not exist"
        continue
    fi


    image_definitions=$(az sig image-definition list --resource-group "$RG" --gallery-name "$GALLERY_NAME" | jq -r '.[] | .name')
    readarray -t images <<< "$image_definitions"
    resource_namespace="Microsoft.Compute"
    resource_type="galleries/images"

    for image in "${images[@]}"; do
        resource_id="/subscriptions/$SUBSCRIPTION/resourceGroups/$RG/providers/$resource_namespace/galleries/$GALLERY_NAME/images/$image"
        locks=$(az lock list --resource $resource_id | jq -r '.[] | .name') 

        if [ -z "$locks" ]; then
            echo "No locks found for Image Definition: $image"
        else
            echo "Locks found for Image Definition: $image"
            echo "Deleting locks..." 
            for lock in $locks; do
                az lock delete --name "$lock" --resource "$resource_id"
            done
        fi
    done
    az sig image-definition list --resource-group $RG --gallery-name $GALLERY_NAME --subscription $SUBSCRIPTION | jq -r '.[] | .name' | while read -r line ; do
        echo "Deleting image definition $line"
        az sig image-version list --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $line --subscription $SUBSCRIPTION | jq -r '.[] | .name' | while read -r version ; do
            echo "Deleting image version $version"
            az sig image-version delete --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $line --gallery-image-version $version --subscription $SUBSCRIPTION
        done
        az sig image-definition delete --resource-group $RG --gallery-name $GALLERY_NAME --gallery-image-definition $line --subscription $SUBSCRIPTION
    done
    az sig share reset --resource-group $RG --gallery-name $GALLERY_NAME
    az sig delete --resource-group $RG --gallery-name $GALLERY_NAME --subscription $SUBSCRIPTION
    echo "Deleted gallery $GALLERY_NAME"
done
