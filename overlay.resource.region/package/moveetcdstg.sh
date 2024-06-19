#!/bin/bash
set -euo pipefail

LEGACY_ETCD_STORAGE_ACCOUNT_SUBSCRIPTION_ID="${REGION_SUBSCRIPTION_ID}"
LEGACY_ETCD_STORAGE_ACCOUNT_RESOURCE_GROUP_NAME="${RESOURCE_NAME_PREFIX}hcp-underlay-${REGION}"
LEGACY_ETCD_BACKUP_STORAGE_ACCOUNT_NAME="${RESOURCE_NAME_PREFIX_NODASH}etcd${REGION}"

exists=$(az storage account show --subscription "${LEGACY_ETCD_STORAGE_ACCOUNT_SUBSCRIPTION_ID}" \
    --resource-group "${LEGACY_ETCD_STORAGE_ACCOUNT_RESOURCE_GROUP_NAME}" \
    --name "${LEGACY_ETCD_BACKUP_STORAGE_ACCOUNT_NAME}" 2>/dev/null || true)

if [[ "$exists" != "" ]]; then
    echo "storage account exists in legacy sub, start moving"
    az resource move --subscription "${LEGACY_ETCD_STORAGE_ACCOUNT_SUBSCRIPTION_ID}" --destination-subscription-id "${OVERLAY_RESOURCES_SUBSCRIPTION_ID}" \
        --destination-group "${OVERLAY_RESOURCE_GROUP_NAME}" \
        --ids "/subscriptions/${LEGACY_ETCD_STORAGE_ACCOUNT_SUBSCRIPTION_ID}/resourceGroups/${LEGACY_ETCD_STORAGE_ACCOUNT_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${LEGACY_ETCD_BACKUP_STORAGE_ACCOUNT_NAME}"
else
    echo "the storage account not exists, skip moving"
fi