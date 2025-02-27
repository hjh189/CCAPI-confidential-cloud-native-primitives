#!/bin/bash

DOCKER_REPO=docker.io/library
NFD_NAME=node-feature-discovery
NFD_NS=node-feature-discovery
NFD_URL=https://kubernetes-sigs.github.io/node-feature-discovery/charts
WORK_DIR=$(cd "$(dirname "$0")" || exit; pwd)
tag=latest
delete_force=false


function usage {
    cat << EOM
usage: $(basename "$0") [OPTION]...
    -r <registry prefix> the prefix string for registry
    -g <tag> container image tag
    -d Delete existing CCNP and install new CCNP
EOM
    exit 1
}

function process_args {
while getopts ":r:g:hd" option; do
        case "${option}" in
            r) registry=${OPTARG};;
            g) tag=${OPTARG};;
            d) delete_force=true;;
            h) usage;;
            *) echo "Invalid option: -${OPTARG}" >&2
               usage
               ;;
        esac
    done

    if [[ -z "$registry" ]]; then
        echo "Error: Please specify your docker registry via -r <registry prefix>."
            exit 1
    fi
}

function check_env {
    if ! command -v helm &> /dev/null
    then
        echo "Helm could not be found. Please install Helm."
        exit
    fi
    if ! command -v kubectl &> /dev/null
    then
        echo "Kubectl could not be found. Please install K8S."
        exit
    fi
}

function delete_ccnp {
    pushd "${WORK_DIR}/../../.." || exit

    echo "-----------Delete ccnp device plugin and NFD..."
    helm uninstall $NFD_NAME --namespace $NFD_NS
    helm uninstall ccnp-device-plugin

    echo "-----------Delete ccnp server..."
    kubectl delete -f deployment/kubernetes/manifests/ccnp-server-deployment.yaml

    echo "-----------Delete ccnp namespace..."
    kubectl delete -f deployment/kubernetes/manifests/namespace.yaml
    popd || exit
}

function deploy_ccnp {
    pushd "${WORK_DIR}/../../.." || exit

    # Generate temporary yaml files for deployment
    mkdir -p temp_manifests
    cp deployment/kubernetes/manifests/* temp_manifests/
    cp device-plugin/ccnp-device-plugin/deploy/helm/ccnp-device-plugin/values.yaml temp_manifests/

    # If private repo is used, modify the images' names in the yaml files
    if [[ -n "$registry" ]]; then
        sed -i  "s#${DOCKER_REPO}#${registry}#g" temp_manifests/*
    fi

    if [[ "$tag" != "latest" ]]; then
        sed -i  "s#latest#${tag}#g" temp_manifests/*
    fi

    # Deploy CCNP Dependencies
    helm repo add nfd $NFD_URL
    helm repo update
    helm install $NFD_NAME  nfd/node-feature-discovery --namespace $NFD_NS --create-namespace

    kubectl apply -f  device-plugin/ccnp-device-plugin/deploy/node-feature-rules.yaml
    helm install ccnp-device-plugin  device-plugin/ccnp-device-plugin/deploy/helm/ccnp-device-plugin

    # Deploy CCNP services
    echo "-----------Deploy ccnp namespace..."
    kubectl create -f temp_manifests/namespace.yaml

    echo "-----------Deploy ccnp server..."
    kubectl create -f temp_manifests/ccnp-server-deployment.yaml

    rm -rf temp_manifests
    popd || exit
}

check_env
process_args "$@"

echo ""
echo "-------------------------"
echo "tag: ${tag}"
echo "registry: ${registry}"
echo "delete_force: ${delete_force}"
echo "-------------------------"
echo ""

if [[ $delete_force == true ]]; then
    delete_ccnp
fi

deploy_ccnp
