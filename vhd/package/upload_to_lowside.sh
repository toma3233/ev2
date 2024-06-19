set -ex
[[ -z "${LOW_SIDE_SUBSCRIPTION_ID}" ]] && echo "LOW_SIDE_SUBSCRIPTION_ID is not set" && exit 1

function main() {
  echo "az account set --subscription ${LOW_SIDE_SUBSCRIPTION_ID}"
  az account set --subscription ${LOW_SIDE_SUBSCRIPTION_ID}
  for i in publishing-info*/*.json; do
    vhd_source="$(cat $i | jq -r '.vhd_url')"
    sku_name="$(cat $i | jq -r '.sku_name')"

    echo "Copying ${sku_name} SKU to low side storage account"
    publish_to_low_side $vhd_source ${LOW_SIDE_AGC_SA_CONTAINER_NAME} ${LOW_SIDE_AGC_SA_NAME} $sku_name
  done
}

function publish_to_low_side() {
  vhd_source=$1
  low_side_sa_container_name=$2
  low_side_sa_name=$3
  sku_name=$4

  vhd_source_without_query_parameters=$(echo ${vhd_source} | sed 's/?.*//')
  file_name=$(echo ${vhd_source_without_query_parameters##*/})

  echo "${sku_name}: Started copying VHD file: ${file_name}"
  az storage blob copy start \
    --destination-blob ${file_name} \
    --destination-container ${low_side_sa_container_name} \
    --account-name ${low_side_sa_name} \
    --subscription ${LOW_SIDE_SUBSCRIPTION_ID} \
    --source-uri ${vhd_source}
}

main
