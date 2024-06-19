#!/bin/bash
set -e

source ./common.servicebus.sh
source ./common.eventgrid.sh

# flt is only enabled in public prod, fairfax and mooncake.
if [[ "$CLOUDENV" != "gb" && "$CLOUDENV" != "ff" && "$CLOUDENV" != "mc" ]]; then exit 0; fi 

FLT_IDENTITY_NAME="${RESOURCE_NAME_PREFIX}flt"

ASSIGNEE=$(az identity show --name "${FLT_IDENTITY_NAME}" \
                            --resource-group "${OVERLAY_RESOURCE_GROUP_NAME}" \
                            --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" \
                            --query "principalId" \
                            -o tsv)

grant_sb_data_owner "$ASSIGNEE" "$SERVICEBUS_NAMESPACE_NAME"

# The script below creates role assignment for flt msi in every region for their respective deployed EGs. see mapping below.
case "${CLOUDENV}-${DEPLOYENV}-${REGION}" in
    gb-prod-eastus)
        SOURCE_REGIONS=(eastus2euap eastus eastus2 canadaeast canadacentral brazilsoutheast brazilsouth northcentralus southcentralus
            westcentralus mexicocentral)
        ;;
    gb-prod-westeurope)
        SOURCE_REGIONS=(germanywestcentral francesouth swedencentral polandcentral francecentral spaincentral westeurope ukwest swedensouth
            germanynorth northeurope switzerlandnorth norwayeast norwaywest switzerlandwest italynorth uksouth southafricanorth
            southafricawest israelcentral centralindia jioindiawest jioindiacentral southindia qatarcentral uaenorth uaecentral)
        ;;
    gb-prod-westus2)
        SOURCE_REGIONS=(staging-westus2 westus westus3 westus2 centralus centraluseuap australiasoutheast australiacentral2 australiacentral
            australiaeast japanwest japaneast koreacentral koreasouth eastasia taiwannorth taiwannorthwest malaysiasouth southeastasia)
        ;;
    ff-prod-usgovvirginia)
        SOURCE_REGIONS=(usgovvirginia usgovarizona usgovtexas)
        ;;
    mc-prod-chinanorth3)
        SOURCE_REGIONS=(chinaeast2 chinanorth3 chinaeast3 chinanorth2)
        ;;
    *)
        SOURCE_REGIONS=()
        ;;
esac

for SOURCE_REGION in "${SOURCE_REGIONS[@]}"; do
    MSI_NAME="flt"
    MSI_RESOURCE_GROUP="overlay-${SOURCE_REGION}"
    if [[ "${SOURCE_REGION}" == "staging-westus2" ]]; then
        MSI_NAME="stg-flt"
        MSI_RESOURCE_GROUP="stg-overlay-westus2"
    fi

    MSI_PRINCIPALID=$(az identity show --name "${MSI_NAME}" \
                    --resource-group "${MSI_RESOURCE_GROUP}" \
                    --subscription "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" \
                    --query "principalId" \
                    -o tsv)

    grant_eg_data_sender "${MSI_PRINCIPALID}" "${ARN_EG_NAME}"
done