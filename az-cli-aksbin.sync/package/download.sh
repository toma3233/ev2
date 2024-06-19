#/bin/bash
set -euo pipefail

release_path=${1-"$PWD/_output/"}
versions=$(cat $release_path/kubectl/versions.txt)

STORAGE_ACCOUNTS=${STORAGE_ACCOUNTS:-"aksteleportusnat aksteleportussec"}


function download {
    local source_base_url=$1
    local destination_base=$2
    local file_path=$3
    local remote_base_url_bias=$4

    isSkip="true"
    for storage_account in ${STORAGE_ACCOUNTS}
    do
        base_url="https://${storage_account}.blob.core.windows.net/${storage_account}/upstream/azure-cli/aks"
        if ! curl ${base_url}/${remote_base_url_bias}/${file_path} --fail --output /dev/null --silent --head; then
        {
            isSkip="false"
            break
        }
        fi
    done

    if [[ $isSkip == "true" ]]; then
    {
        echo "skip ${remote_base_url_bias}: ${file_path}"
        return
    }
    fi
    

    source_url=${source_base_url}/${file_path}
    destination=${destination_base}/${file_path}

    destination_path=$(dirname $destination)
    mkdir -p $destination_path
    curl -Ls "$source_url" --output $destination
}


echo Start download kubectl
for version in $versions
do
{
    echo start downloading kubectl $version

    download "https://dl.k8s.io/release" "$release_path/kubectl" "$version/bin/linux/amd64/kubectl" kubectl
    download "https://dl.k8s.io/release" "$release_path/kubectl" "$version/bin/windows/amd64/kubectl.exe" kubectl

    echo Complete downloaded kubectl $version
}&
done
wait

echo Start download kubelogin
versions=$(cat $release_path/kubelogin/versions.txt)
for version in $versions
do
{
    echo start downloading kubelogin $version to $release_path/kubelogin/$version

    download "https://github.com/Azure/kubelogin/releases/download" "$release_path/kubelogin" "$version/kubelogin.zip" kubelogin

    echo Complete downloaded kubelogin $version
}&
done
wait