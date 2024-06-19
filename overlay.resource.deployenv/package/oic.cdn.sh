#!/bin/bash

set -euo pipefail

if [[ -z "${OIC_AZURE_CDN_FRONTDOOR_OBJECTID:-""}" ]]; then
    echo "OIC_AZURE_CDN_FRONTDOOR_OBJECTID not set, skipping OIDC CDN setup"
    exit 0
fi

OIC_CDN_SUBSCRIPTION="${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"
OIC_CDN_LOCATION="global"
OIC_CDN_RESOURCE_GROUP="${RESOURCE_NAME_PREFIX}overlay-global"
OIC_CDN_PROFILE_NAME="${RESOURCE_NAME_PREFIX_NODASH}aksoic"
OIC_CDN_ENDPOINT_NAME="${RESOURCE_NAME_PREFIX_NODASH}aksoic"
OIC_CDN_SKU="Standard_Microsoft"
OIC_CDN_CUSTOM_DOMAIN_HOSTNAME="oidc.${DOMAIN_DEPLOYENV}"
# oidc.<domain_name> -> oidc-<domain_name>
OIC_CDN_CUSTOM_DOMAIN_NAME="$(echo "${OIC_CDN_CUSTOM_DOMAIN_HOSTNAME}" | sed -r 's/\./-/g')"

OIC_STORAGE_ACCOUNT_SUBSCRIPTION="${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"
OIC_STORAGE_ACCOUNT_RESOURCE_GROUP="${RESOURCE_NAME_PREFIX}overlay-global"
OIC_STORAGE_ACCOUNT_NAME="${RESOURCE_NAME_PREFIX_NODASH}aksoic"

OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_SUBSCRIPTION="${OVERLAY_RESOURCES_SUBSCRIPTION_ID}"
OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_RESOURCE_GROUP="${RESOURCE_NAME_PREFIX}overlay-global"
OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_NAME="${RESOURCE_NAME_PREFIX}aksoic"
OIC_CUSTOM_DOMAIN_SSL_CERT_SECRET_NAME="ssl"

echo "Granting keyvault access to OIDC CDN"

az keyvault set-policy \
    --subscription "${OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_SUBSCRIPTION}" \
    --resource-group "${OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_RESOURCE_GROUP}" \
    --name "${OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_NAME}" \
    --secret-permissions get list \
    --certificate-permissions get list \
    --object-id "${OIC_AZURE_CDN_FRONTDOOR_OBJECTID}"

echo "Granted keyvault access to OIDC CDN"

echo "Creating OIDC global CDN profile"

az cdn profile create \
    --subscription "${OIC_CDN_SUBSCRIPTION}" \
    --location "${OIC_CDN_LOCATION}" \
    --resource-group "${OIC_CDN_RESOURCE_GROUP}" \
    --name "${OIC_CDN_PROFILE_NAME}" \
    --sku "${OIC_CDN_SKU}"

echo "Created OIDC global CDN profile"

echo "Requesting OIDC storage account detials"

storage_account_details=$(az storage account show \
    --subscription "${OIC_STORAGE_ACCOUNT_SUBSCRIPTION}" \
    --resource-group "${OIC_STORAGE_ACCOUNT_RESOURCE_GROUP}" \
    --name "${OIC_STORAGE_ACCOUNT_NAME}")

OIC_STORAGE_ACCOUNT_BLOB_HOSTNAME=$(echo "$storage_account_details" \
    | jq -r '.primaryEndpoints.blob' \
    | sed -r 's/^https:\/\///g' \
    | sed -r 's/\/$//g')

echo "OIDC storage account blob hostname is ${OIC_STORAGE_ACCOUNT_BLOB_HOSTNAME}"

# NOTE: we use ARM template to setup deliver policy, which is not well supported by az cli.
az deployment group create \
    --name "${OIC_CDN_ENDPOINT_NAME}-deployment" \
    --resource-group "${OIC_CDN_RESOURCE_GROUP}" \
    --template-file "./oic.cdn.template.json" \
    --parameters \
        "resource_name_prefix_nodash=${RESOURCE_NAME_PREFIX_NODASH}" \
        "oic_cdn_endpoint_name=${OIC_CDN_ENDPOINT_NAME}" \
        "oic_domain_dnszone_name=${DOMAIN_DEPLOYENV}" \
        "oic_storage_account_blob_hostname=${OIC_STORAGE_ACCOUNT_BLOB_HOSTNAME}"

echo "OIDC CDN endpoint ${OIC_CDN_ENDPOINT_NAME} created"

if az cdn custom-domain show \
    --subscription "${OIC_CDN_SUBSCRIPTION}" \
    --resource-group "${OIC_CDN_RESOURCE_GROUP}" \
    --profile-name "${OIC_CDN_PROFILE_NAME}" \
    --endpoint-name "${OIC_CDN_ENDPOINT_NAME}" \
    --name "${OIC_CDN_CUSTOM_DOMAIN_NAME}" > /dev/null 2>&1; then
    echo "OIDC custom domain ${OIC_CDN_CUSTOM_DOMAIN_NAME} already exists"
else
    echo "Creating OIDC custom domain ${OIC_CDN_CUSTOM_DOMAIN_NAME} with HTTPS"

    az cdn custom-domain create \
        --subscription "${OIC_CDN_SUBSCRIPTION}" \
        --location "${OIC_CDN_LOCATION}" \
        --resource-group "${OIC_CDN_RESOURCE_GROUP}" \
        --profile-name "${OIC_CDN_PROFILE_NAME}" \
        --endpoint-name "${OIC_CDN_ENDPOINT_NAME}" \
        --name "${OIC_CDN_CUSTOM_DOMAIN_NAME}" \
        --hostname "${OIC_CDN_CUSTOM_DOMAIN_HOSTNAME}"

    az cdn custom-domain enable-https \
        --subscription "${OIC_CDN_SUBSCRIPTION}" \
        --resource-group "${OIC_CDN_RESOURCE_GROUP}" \
        --profile-name "${OIC_CDN_PROFILE_NAME}" \
        --endpoint-name "${OIC_CDN_ENDPOINT_NAME}" \
        --name "${OIC_CDN_CUSTOM_DOMAIN_NAME}" \
        --min-tls-version "1.2" \
        --user-cert-subscription-id "${OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_SUBSCRIPTION}" \
        --user-cert-group-name "${OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_RESOURCE_GROUP}" \
        --user-cert-protocol-type "sni" \
        --user-cert-vault-name "${OIC_CUSTOM_DOMAIN_SSL_CERT_KEY_VAULT_NAME}" \
        --user-cert-secret-name "${OIC_CUSTOM_DOMAIN_SSL_CERT_SECRET_NAME}"

    echo "Created OIDC custom domain ${OIC_CDN_CUSTOM_DOMAIN_NAME} with HTTPS"
fi