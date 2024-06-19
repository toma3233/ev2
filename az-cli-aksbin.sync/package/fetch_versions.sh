
#/bin/bash
set -euo pipefail

release_dir=${1-"$PWD/_output"}

function fetch_kubectl_versions() {
    release_dir=$1
    output_dir=$release_dir/kubectl
    mkdir -p $output_dir
    echo "Fetching stable version from dl.k8s.io/release/stable.txt"
    curl -L -s https://dl.k8s.io/release/stable.txt > $output_dir/stable.txt

    curl -L -s https://api.github.com/repos/kubernetes/kubernetes/tags | jq -r .[].name | grep "v1\.2[[:digit:]]\.[[:digit:]]*$"  > $output_dir/versions.txt

    echo
    echo "Verify stable version exists in versions"
    if  cat $output_dir/versions.txt | grep $(cat $output_dir/stable.txt)$ ; then
        echo "stable version exists, fetch version completed"
    else
        echo "Error: latest kubectl version miss"
        exit 1
    fi
}

function fetch_kubelogin_versions() {
    release_dir=$1
    output_dir=$release_dir/kubelogin
    mkdir -p $output_dir
    echo "Fetching kubectl versions from github https://github.com/Azure/kubelogin"
    curl -L -s https://api.github.com/repos/Azure/kubelogin/releases | jq -r .[].tag_name > $output_dir/versions.txt

    echo
    echo "Fetching the lastest stable version from https://api.github.com/repos/Azure/kubelogin/releases/latest"
    curl -L -s https://api.github.com/repos/Azure/kubelogin/releases/latest > $output_dir/latest
}

fetch_kubectl_versions $release_dir
fetch_kubelogin_versions $release_dir