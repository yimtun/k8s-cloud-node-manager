#!/bin/bash

# name: get_kubeconfig_from_sa.sh

#
if [ "$#" -ne 1 ]; then
    echo "usage: $0 <namespace>"
    echo "usage: $0 default"
    exit 1
fi

NAMESPACE=$1

#
echo "get ServiceAccount token..."
SA_TOKEN=$(kubectl get secret node-restarter-token -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d)

#
echo "get cluster info..."
CLUSTER_NAME=$(kubectl config current-context)
CLUSTER_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
API_SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')

#  create new  kubeconfig
echo " create  kubeconfig file..."
cat << EOF > node-restarter-kubeconfig
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${API_SERVER}
contexts:
- name: node-restarter-context
  context:
    cluster: ${CLUSTER_NAME}
    user: node-restarter
    namespace: $NAMESPACE
current-context: node-restarter-context
users:
- name: node-restarter
  user:
    token: ${SA_TOKEN}
EOF

echo "created : node-restarter-kubeconfig"
echo ""
echo "usage:"
echo "1. use --kubeonfig:"
echo "   kubectl --kubeconfig=node-restarter-kubeconfig get node <nodename>"
echo "   kubectl --kubeconfig=node-restarter-kubeconfig restart <nodename>"
echo ""
echo "2. use KUBECONFIG env:"
echo "   mkdir -p ~/.kube/restricted-configs"
echo "   cp node-restarter-kubeconfig ~/.kube/restricted-configs/"
echo ""
echo "3. define env:"
echo "   export KUBECONFIG=~/.kube/restricted-configs/node-restarter-kubeconfig"
echo ""
echo "4. recover default env:"
echo "   export KUBECONFIG=~/.kube/config"