#/bin/bash
set -euo pipefail

release_dir="${PWD}/_output"
mkdir -p $release_dir

bash ./fetch_versions.sh $release_dir
bash ./download.sh $release_dir
for storage_account in ${STORAGE_ACCOUNTS}
do
    if [[ $(az storage container exists --name $storage_account --account-name $storage_account --query 'exists') == false ]];then
        echo "container $storage_account does not exist in storage account $storage_account"
        exit 1
    fi
    az config set extension.use_dynamic_install=yes_without_prompt
    az storage blob directory upload -c $storage_account --account-name $storage_account -s "$release_dir/*" -d upstream/azure-cli/aks --recursive
done
