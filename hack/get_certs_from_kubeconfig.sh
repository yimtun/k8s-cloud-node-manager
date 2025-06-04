#!/bin/bash
KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
CURRENT_CONTEXT=$(kubectl config view --raw -o jsonpath='{.current-context}')
CLUSTER_NAME=$(kubectl config view --raw -o jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.cluster}")
USER_NAME=$(kubectl config view --raw -o jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.user}")


kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority-data}" | base64 -d > /tmp/ca.crt
kubectl config view --raw -o jsonpath="{.users[?(@.name==\"$USER_NAME\")].user.client-certificate-data}" | base64 -d > /tmp/client.crt
kubectl config view --raw -o jsonpath="{.users[?(@.name==\"$USER_NAME\")].user.client-key-data}" | base64 -d > /tmp/client.key
