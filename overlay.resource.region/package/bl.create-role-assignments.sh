#!/bin/bash
set -euo

# The contents of this script are tasks that can't yet be done with Ev2+ARM. As
# these features become available in Ev2/ARM, we should remove this script.

PAV2_VALUE_NAME_BASE=aksblp

pav_sa_rg="${RESOURCE_NAME_PREFIX}Feature.PAv2-${REGION}"
pav_sa_name="${RESOURCE_NAME_PREFIX_NODASH}${PAV2_VALUE_NAME_BASE}${REGION_SHORT_NAME}"
pav_sa_id=$(az storage account show -g ${pav_sa_rg} -n ${pav_sa_name} --query id --output tsv)

# Assign Azure Key Vault service the "Storage Account Key Operator Service Role" role
# 81a9662b-bebf-436f-a333-f67b29880f12 is the ID of the role
az role assignment create \
    --role "81a9662b-bebf-436f-a333-f67b29880f12" \
    --scope $pav_sa_id \
    --assignee-object-id ${AZURE_KEYVAULT_OBJECTID}

EV2_MSI_OBJECTID=$(az identity show --ids "${MSI_OPERATOR_RESOURCE_ID}" --query principalId -o tsv 2>/dev/null || echo "")
if [ "${EV2_MSI_OBJECTID}" == "" ]; then
  echo "failed to show msi operator ${MSI_OPERATOR_RESOURCE_ID}"
  exit 1
fi
az role assignment create \
    --role "Storage Account Contributor" \
    --assignee-object-id "${EV2_MSI_OBJECTID}" \
    --scope "${pav_sa_id}"
