#!/bin/bash

# sh get_kubeconfig_from_token.sh  default extended-api-server-token

#
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#
show_usage() {
    echo -e "${YELLOW}usage: $0 <namespace> [token-name]${NC}"
    echo -e "${YELLOW}arg:${NC}"
    echo "  namespace    : Kubernetes ns"
    echo "  token-name   : (option) ServiceAccount token name default is  'node-restarter-token'"
    echo -e "${YELLOW}ex:${NC}"
    echo "  $0 default                    #  token "
    echo "  $0 default my-custom-token    #  token "
    exit 1
}

#
error_exit() {
    echo -e "${RED}err: $1${NC}" >&2
    exit 1
}

#
check_requirements() {
    local required_commands=("kubectl" "base64")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error_exit "err: $cmd"
        fi
    done
}

#
check_kubectl_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "can't connect Kubernetes cluster"
    fi
}

#
check_namespace() {
    if ! kubectl get namespace "$1" &> /dev/null; then
        error_exit "ns '$1' err"
    fi
}

#
check_resources() {
    local namespace=$1
    local token_name=$2
    local sa_name=${token_name%-token}  # use token name get  ServiceAccount name

    if ! kubectl get serviceaccount "$sa_name" -n "$namespace" &> /dev/null; then
        error_exit "ServiceAccount '$sa_name' ns '$namespace' err"
    fi
    if ! kubectl get secret "$token_name" -n "$namespace" &> /dev/null; then
        error_exit "Secret '$token_name' ns '$namespace' err"
    fi
}

#
main() {
    #
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        show_usage
    fi

    local NAMESPACE=$1
    local TOKEN_NAME=${2:-"node-restarter-token"}  #
    local SA_NAME=${TOKEN_NAME%-token}             #
    local CONFIG_FILE="${SA_NAME}-kubeconfig"
    local CURRENT_DIR=$(pwd)
    local PARENT_DIR=$(dirname "$CURRENT_DIR")
    local FULL_PATH="${PARENT_DIR}/${CONFIG_FILE}"

    #
    echo -e "${GREEN}check env...${NC}"
    check_requirements
    check_kubectl_connection
    check_namespace "$NAMESPACE"
    check_resources "$NAMESPACE" "$TOKEN_NAME"

    #  token
    echo -e "${GREEN}get ServiceAccount token...${NC}"
    local SA_TOKEN
    SA_TOKEN=$(kubectl get secret "$TOKEN_NAME" -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d) || \
        error_exit "get token err"

    #
    echo -e "${GREEN}get cluster info...${NC}"
    local CLUSTER_NAME
    local CLUSTER_CA
    local API_SERVER

    #
    CLUSTER_NAME=$(kubectl config current-context) || error_exit "err"

    #
    local CURRENT_CLUSTER
    CURRENT_CLUSTER=$(kubectl config view --raw -o jsonpath="{.contexts[?(@.name==\"$CLUSTER_NAME\")].context.cluster}") || \
        error_exit "err"

    #
    API_SERVER=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CURRENT_CLUSTER\")].cluster.server}") || \
        error_exit "get API Server err"
    CLUSTER_CA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CURRENT_CLUSTER\")].cluster.certificate-authority-data}") || \
        error_exit "get CA err"

    #  kubeconfig
    echo -e "${GREEN}new kubeconfig file...${NC}"
    cat << EOF > "$FULL_PATH"
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${API_SERVER}
contexts:
- name: ${SA_NAME}-context
  context:
    cluster: ${CLUSTER_NAME}
    user: ${SA_NAME}
    namespace: $NAMESPACE
current-context: ${SA_NAME}-context
users:
- name: ${SA_NAME}
  user:
    token: ${SA_TOKEN}
EOF

    #
    chmod 600 "$FULL_PATH"

    echo -e "${GREEN}: $FULL_PATH${NC}"
    echo ""
    echo -e "${YELLOW}info:${NC}"
    echo "ns: $NAMESPACE"
    echo "ServiceAccount: $SA_NAME"
    echo "Token Secret: $TOKEN_NAME"
    echo ""
    echo -e "${YELLOW}usage:${NC}"
    echo "1. use --kubeconfig:"
    echo "   kubectl --kubeconfig=$CONFIG_FILE get nodes"
    echo "   kubectl --kubeconfig=$CONFIG_FILE get node <nodename>"
    echo ""
    echo "2. use env KUBECONFIG:"
    echo "   export KUBECONFIG=$FULL_PATH"
    echo ""
    echo "3. recover default env KUBECONFIG:"
    echo "   export KUBECONFIG=~/.kube/config"
    echo ""
    echo -e "${YELLOW}warn:${NC}"
    echo "- file privilege  600"
}

#
main "$@"