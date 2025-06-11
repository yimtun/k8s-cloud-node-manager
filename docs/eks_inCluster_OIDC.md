# Running in EKS Cluster with OIDC Enabled

- After enabling OIDC support in EKS, the k8s-cloud-node-manager running in Pods can access AWS API through ServiceAccount, which is the recommended access method by AWS

- In this document, the working directory for running shell commands is the docs directory under the project root. When editing this document and verifying commands, the IDE can recognize shell commands in md files and can click directly in md to run them, which will automatically create a terminal and execute the command. Therefore, there will be a cd command to switch paths before each command

- Prerequisites: Install and configure awscli, install terraform

## Using Example Terraform to Create EKS Cluster with OIDC Support

```shell
cd ../examples/oidc_eks_tf/
terraform apply
```

The RBAC is already configured in the terraform, so there's no need to execute `deploy/inCluster/rbac.yaml` later.

## Get EKS Kubeconfig File

```shell
cd ..
aws eks update-kubeconfig --name my-eks-cluster --region us-east-1 --kubeconfig ./config-eks
```

## Generate Certificates

```shell
cd ../hack
sh gen.sh
```

**Copy the content from file `certs/caBundle.txt` to the `caBundle` field in file `deploy/apiservice.yaml`**

## Create Secret for Storing TLS Certificates

```shell
cd ..
kubectl --kubeconfig ./config-eks delete secret extended-api-tls -n default
kubectl --kubeconfig ./config-eks create secret tls extended-api-tls --cert=./certs/tls.crt --key=./certs/tls.key -n default
```

**Although this is a single AWS cluster, we still choose to create an empty tencentcloud-credentials to avoid secretKeyRef errors**

```shell
cd ..
kubectl --kubeconfig ./config-eks delete secret tencentcloud-credentials -n default
kubectl --kubeconfig ./config-eks create secret generic tencentcloud-credentials \
  --from-literal=TENCENTCLOUD_SECRET_ID="xxxx" \
  --from-literal=TENCENTCLOUD_SECRET_KEY="xxxx" \
  -n default
```

## Apply Manifest Files

Since we're using EKS OIDC, we need to execute `eks_oidc_deployment.yaml`

```shell
cd ..
kubectl --kubeconfig ./config-eks  apply -f deploy/inCluster/eks_oidc_deployment.yaml  -n default
```

```shell
cd ..
kubectl --kubeconfig ./config-eks  apply -f deploy/apiservice.yaml  -n default
```

```shell
cd ..
kubectl --kubeconfig ./config-eks  apply -f deploy/inCluster/service.yaml  -n default
```

## Check APIService Status

```shell
cd ..
kubectl --kubeconfig ./config-eks   get apiservice v1.infraops.michael.io
```

Output display:

```text
NAME                     SERVICE                    AVAILABLE   AGE
v1.infraops.michael.io   default/infraops-service   True        36s
```

## View API Documentation

```shell
cd ..
kubectl --kubeconfig ./config-eks get --raw   "/apis/infraops.michael.io/v1" | jq .
```

Output display:

```json
{
  "apiVersion": "v1",
  "groupVersion": "infraops.michael.io/v1",
  "kind": "APIResourceList",
  "resources": [
    {
      "kind": "Node",
      "name": "nodes",
      "namespaced": false,
      "singularName": "node",
      "verbs": [
        "get",
        "list"
      ]
    },
    {
      "kind": "Node",
      "name": "nodes/restart",
      "namespaced": false,
      "singularName": "",
      "verbs": [
        "post"
      ]
    }
  ]
}
```

**Currently using core resource nodes, so the nodes resource related interfaces in the above output json file are not implemented**

## Testing

The following two testing methods can demonstrate that the AA here is essentially still an ordinary HTTP interface.

### Curl Command Testing Interface

Get CA from config-eks

```shell
cd ..
export KUBECONFIG=./config-eks
CURRENT_CONTEXT=$(kubectl  config view --raw -o jsonpath='{.current-context}')
CLUSTER_NAME=$(kubectl     config view --raw -o jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.cluster}")
USER_NAME=$(kubectl        config view --raw -o jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.user}")
kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority-data}" | base64 -d > /tmp/ca.crt
```

Get token

```shell
aws eks get-token --cluster-name my-eks-cluster  --region us-east-1 | jq -r '.status.token'  > /tmp/token
```

Get k8s api endpoint

```shell
cd ..
export KUBECONFIG=./config-eks
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
```

Output display:

```shell
https://DA9C70C8535A5ADDE9C74C3600756B25.gr7.us-east-1.eks.amazonaws.com
```

Curl test command

```shell
curl -X POST \
  --cacert /tmp/ca.crt \
  -H "Authorization: Bearer $(cat /tmp/token)" \
  "https://DA9C70C8535A5ADDE9C74C3600756B25.gr7.us-east-1.eks.amazonaws.com/apis/infraops.michael.io/v1/nodes/testNODE/restart"
```

Output display:

```text
Failed to get node testNODE: nodes "testNODE" not found
```

This call is normal because there really is no such node.

### Kubectl Plugin Method Testing

Install kubectl plugin

```shell
go build  -o /usr/local/bin/kubectl-restart ../kubectlplugins/kubectl-restart.go
```

```shell
cd ..
kubectl --kubeconfig ./config-eks get node
```

Output display:

```text
kubectl --kubeconfig ./config-eks get node
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-10-98.ec2.internal    Ready    <none>   12m   v1.32.3-eks-473151a
ip-10-0-11-190.ec2.internal   Ready    <none>   12m   v1.32.3-eks-473151a
```

This shows that the data source used here is actually the k8s core resource nodes.

Restart node

```shell
cd ..
export KUBECONFIG=./config-eks
kubectl  restart ip-10-0-11-190.ec2.internal
```

Output display:

```text
Using exec authentication: aws [--region us-east-1 eks get-token --cluster-name my-eks-cluster]
Request failed, status code: 500, response: you can't rebootip-10-0-11-190.ec2.internalbecause I run on it
```

The k8s-cloud-node-manager uses Downward API to determine that the k8s-cloud-node-manager pod is running on node ip-10-0-11-190.ec2.internal, so it terminates the restart node suicide behavior.

We can confirm this

```shell
cd ..
export KUBECONFIG=./config-eks
kubectl  get pod -o wide
```

Output display:

```text
NAME                                   READY   STATUS    RESTARTS   AGE   IP            NODE                          NOMINATED NODE   READINESS GATES
extended-api-server-566b9954b7-8bv9l   1/1     Running   0          12m   10.0.11.206   ip-10-0-11-190.ec2.internal   <none>           <none>
```

Now restart another node

```shell
cd ..
export KUBECONFIG=./config-eks
kubectl  restart ip-10-0-10-98.ec2.internal
```

Output display:

```text
Using exec authentication: aws [--region us-east-1 eks get-token --cluster-name my-eks-cluster]
Node ip-10-0-10-98.ec2.internal (providerID: aws:///us-east-1a/i-0da7c9af35266791d, instance ID: i-0da7c9af35266791d, cloud provider: AWS) has been restarted
```

Wait for the server to restart, then you can log into the server to verify

```shell
aws ssm start-session --target  i-0da7c9af35266791d    --region=us-east-1 
```

## Destroy Test EKS Cluster

```shell
cd ../examples/oidc_eks_tf/
terraform destroy
```
