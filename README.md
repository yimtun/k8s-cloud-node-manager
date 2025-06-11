# k8s-cloud-node-manager

[🇨🇳 切换到中文版本](README_CN.md)

> **Extends Kubernetes through API Aggregation (AA) mechanism to unify cloud server management work related to Kubernetes in Kubernetes interfaces, demonstrating a lightweight implementation without registering resources**

**Project Features:**

- Supports connecting and managing nodes from different cloud providers like AWS, Tencent Cloud, etc. within a single Kubernetes cluster (the high-performance universal CNI involved in this architecture will be implemented in another project), achieving unified operation and maintenance of multi-cloud nodes.
- For cloud provider-managed Kubernetes clusters (such as AWS EKS, Tencent Cloud TKE), this project provides native support.
- Automatically identifies cloud provider types and obtains cloud server IDs through the node ProviderID format of each cloud provider's managed cluster. Self-built clusters need to ensure the ProviderID format is consistent with the corresponding cloud provider, which can be set manually or implemented with other tools during self-building.
- No frameworks or underlying libraries are used for implementation, such as apiserver-builder-alpha and k8s.io/code-generator, demonstrating a different approach - not registering AA resources to k8s, only exposing standard Kubernetes-style API endpoints through the API Aggregation (AA) mechanism to achieve business requirements, which is a lightweight implementation.
- Unifies cloud server operations on cloud node nodes into Kubernetes standard interfaces, leveraging Kubernetes RBAC to control cloud server resource operation permissions. For example, developers don't need to have cloud provider accounts to operate on development nodes.
- Can be applied to chaos engineering. Through AA-extended interfaces, the data source used is the current cluster's core resource nodes, reducing the likelihood of errors.
- Secure and strict deployment method involving the use of self-signed certificates and mandatory CA verification.

---

## Overview

k8s-cloud-node-manager is an API extension implemented based on the Kubernetes API Server Aggregation (AA) mechanism.

Unlike CustomResourceDefinition (CRD), which is declarative and handled by the Kubernetes control plane, AA allows us to deploy independent API servers to provide specialized implementations for custom resources. The main API server delegates requests for custom APIs to this extension server, making them available to all clients. This approach enables us to implement complex business logic (such as calling cloud provider APIs to restart nodes) while maintaining Kubernetes API standards. It supports both in-cluster and out-of-cluster deployment methods and provides a kubectl plugin for convenient node operations.

The following sections will introduce the main methods of Kubernetes extension and the rationale for this project's approach.

---

## Kubernetes API Extension Methods and Selection

Official documentation is somewhat confusing in terms of extension development expression. The following is organized and summarized based on practical experience.

### Ways to Create Kubernetes Custom Resources

Kubernetes provides two ways to add custom resources to a cluster:

- **CustomResourceDefinition (CRD)**
- **API Aggregation (AA)**

> Reference: [Kubernetes API Extension Methods](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/)

### Summary of CRD and AA Practical Usage Scenarios

In actual development, **CRD and AA can be flexibly combined based on business requirements** - they are not mutually exclusive. Common patterns include:

1. **CRD Only**
   Only declares resource types without processing data. **Rarely used this way** unless just for storing information.

2. **CRD + Custom Controller**
   **The most common Operator pattern**, i.e., "declare resources + automated management", is the standard implementation method for Operators with extensive open-source projects and community resources.

3. **AA Interface Only, No AA Resource Registration**
   Does not register AA resources to Kubernetes, only exposes standard Kubernetes API-style endpoints.
   AA-type custom resources don't need to be registered to Kubernetes, directly extending APIs through API aggregation. **Suitable for scenarios where custom API behaviors need to be managed by k8s**. This is the approach adopted by this project.

4. **AA + Custom Controller**
   Custom resources need to be registered to Kubernetes, also an Operator pattern, such as the example project kubernetes/staging/src/k8s.io/sample-apiserver.

5. **CRD + Custom Controller + AA**
   Such as kubevirt, suitable for complex business scenarios that require resource declaration, automated management, and custom API behaviors (such as aggregation, cross-resource operations, etc.). This pattern can be seen as a **high-level Operator implementation**.

### This Project's Selection Rationale

This project adopts the AA-only pattern, mainly based on the following considerations:

1. **Action-Type Subresource Support**
   The restart functionality in this project is an action-type subresource, similar to Kubernetes built-in log, exec, etc. Such subresources can only be implemented through AA. CRD only supports status and scale, two built-in subresources, which cannot meet the requirements.

2. **Imperative Interface Requirements**
   This project needs to implement imperative interfaces like `/restart` for directly triggering node restart operations. Such interfaces don't belong to Kubernetes traditional declarative APIs and cannot be directly implemented through CRD, while the AA mechanism provides flexible support for such operations.

3. **No Need for Controller Watching and Reconciliation (watch and reconcile)**
   This project doesn't need to register AA resources (`apis/infraops.michael.io/v1/nodes`). In fact, the data source reuses core resources (`/api/v1/nodes`) and doesn't need to watch and reconcile other resources, so no Custom Controller is needed, eliminating the need for the AA + Custom Controller pattern.
   From the user's perspective, it's like adding a restart subresource to core resources: `kubectl restart nodeName`

---

## Features

- **Multi-Cloud Support:** Manage nodes on AWS, Tencent Cloud, etc.
- **Kubernetes API Extension:** Provides `/apis/infraops.michael.io/v1` endpoints.
- **Node Restart API:** Restart nodes through standard Kubernetes API or kubectl plugin.
- **Flexible Deployment:** Supports both in-cluster and out-of-cluster modes.
- **Secure Communication:** Uses HTTPS and Kubernetes RBAC.

---

## Quick Start

### Prerequisites

1. **Generate Certificates**

```bash
cd hack
sh gen.sh
```

- If you need to modify IP/namespace, please edit `hack/gen.sh` and replace default with your custom namespace.
- If using ExternalName Service to run k8s-cloud-node-manager outside the Kubernetes cluster, please modify the hack/gen.sh script before generating certificates to ensure the correct subjectAltName is set when issuing certificates. For the current example, replace IP:10.211.55.2 content.
- The script will generate certificates in the `certs/` directory and generate the file `certs/caBundle.txt`. The content of this file is used to fill the caBundle in the deploy/apiservice.yaml file. Please be sure to configure this file after generating certificates.

If deploying k8s-cloud-node-manager inside Kubernetes, you need to create a tls secret for the pod to load when the program starts:

```shell
kubectl create secret tls extended-api-tls --cert=certs/tls.crt --key=certs/tls.key -n default
```

2. **Create Secret to Store Cloud Provider Credentials**

For scenarios running inside Kubernetes clusters, you need to configure cloud provider API call credentials on Kubernetes. Secrets are divided into the following scenarios:

- If the cluster is TKE or a self-built Kubernetes cluster on Tencent Cloud, it belongs to a single cloud environment and only needs to configure the secret `tencentcloud-credentials`.

- If the cluster is EKS without OIDC enabled or a self-built Kubernetes cluster on AWS, it belongs to a single cloud environment and only needs to configure the secret `aws-credentials`.

- If the cluster is EKS with OIDC enabled, it belongs to a single cloud environment but doesn't need to configure the secret `aws-credentials`.

- If it's a self-built cluster and uses cloud servers from both Tencent Cloud and AWS as node nodes, it belongs to a multi-cloud environment and needs to configure both secrets `aws-credentials` and `tencentcloud-credentials`.

Commands to configure credentials secrets:

Tencent Cloud:
```shell
kubectl create secret generic tencentcloud-credentials \
     --from-literal=TENCENTCLOUD_SECRET_ID=xxx \
     --from-literal=TENCENTCLOUD_SECRET_KEY=xxx -n default
```

AWS:
```shell
kubectl delete secret aws-credentials -n default
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID="xxxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxxx" \
  -n default
```

You can use the following command to get your AWS key ID and access key:
```shell
cat  ~/.aws/credentials
```

./config-eks is an EKS kubeconfig file generated using the following command:

```shell
aws eks update-kubeconfig --name my-eks-cluster --region us-east-1 --kubeconfig ./config-eks
```

Note: In single-cloud scenarios running inside k8s clusters, you can modify the env configuration in files deploy/inCluster/deployment.yaml and deploy/inCluster/eks_oidc_deployment.yaml according to the situation to avoid errors when the secret in secretKeyRef doesn't exist. Of course, you can also not modify it and directly create an empty secret with the corresponding name.

### Deployment Method Selection

- Except for OIDC-enabled EKS which doesn't support out-of-cluster deployment, other scenarios support both out-of-cluster and in-cluster deployment methods.
- Unless for development and debugging, in-cluster deployment is recommended in all environments.

Based on the above considerations, this project currently provides deployment documentation for the following environments:

1. **Deploy in Self-Built Clusters**
   - Suitable for self-built Kubernetes clusters
   - Suitable for multi-cloud environments
   - [Detailed Deployment Guide](docs/inCluster_CN.md)

2. **Deploy in OIDC-Enabled EKS Clusters**
   - Supports EKS OIDC authentication
   - Suitable for AWS managed clusters, single cloud environment
   - [Detailed Deployment Guide](docs/eks_inCluster_OIDC_CN.md)

3. **Deploy in Non-OIDC EKS Clusters**
   - Suitable for AWS managed clusters, single cloud environment
   - [Detailed Deployment Guide](docs/eks_inCluster_CN.md)

4. **Deploy in TKE Clusters**
   - Suitable for TKE managed clusters, single cloud environment
   - [Detailed Deployment Guide](docs/tke_inCluster_CN.md)

5. **Out-of-Cluster Deployment (Development Environment)**
   - Suitable for self-built Kubernetes clusters
   - Suitable for development and debugging
   - Supports local running
   - Suitable for multi-cloud environments
   - [Detailed Deployment Guide](docs/out-of-band-deployment.md)

### Verify Deployment

1. Check API Service Status

Check if AA is available:

```shell
kubectl  get apiservice v1.infraops.michael.io
```

Output:
```text
NAME                     SERVICE                    AVAILABLE   AGE
v1.infraops.michael.io   default/infraops-service   True        18m
```

View API documentation:

```shell
kubectl get --raw "/apis/infraops.michael.io/v1" | jq .
```

---

## API Usage

### curl Calls

Need to determine certs ??

- Restart node:
  ```bash
  curl -X POST \
    --cacert ./certs/ca.crt \ 
    --cert ./certs/tls.crt \
    --key  ./certs/tls.key \
    "https://<apiserver-ip>:/apis/infraops.michael.io/v1/nodes/<nodename>/restart"
  ```

---

### kubectl Calls

- Build and install kubectl plugin:
  ```bash
  go build -o /usr/local/bin/kubectl-restart kubectlplugins/kubectl-restart.go
  ```

- Usage:

Get node nodes:
  ```bash
  kubectl get node
  ```

Select a node to test restart:
  ```bash
  kubectl restart <nodename>
  ```

## Testing - Using Kubernetes Permission System to Protect Interfaces

Create a restricted Kubernetes user:

```shell
kubectl apply -f e2e/rbac.yaml
```

```shell
sh ./e2e/get_kubeconfig_from_sa.sh default
```

```shell
export KUBECONFIG=./node-restarter-kubeconfig
```

```shell
kubectl   restart  10.205.13.240
```

Output:
```text
Using Token authentication
Request failed, status code: 500, response: Failed to get node 10.205.13.240: nodes "10.205.13.240" not found
```

This output complies with the definition in e2e/rbac.yaml. Although no node was found currently, this has actually passed Kubernetes permission verification.

```shell
kubectl   restart  10.205.13.241
```

Output:
```text
Using Token authentication
Request failed, status code: 403, response: {"kind":"Status","apiVersion":"v1","metadata":{},"status":"Failure","message":"nodes.infraops.michael.io \"10.205.13.24idden: User \"system:serviceaccount:default:node-restarter\" cannot create resource \"nodes/restart\" in API group \"infraops.michael.io\" at the cluster scope","reason":"Forbidden","details":{"name":"10.205.13.241","group":"infraops.michael.io","kind":"nodes"},"code":403}
```

This output complies with the definition in e2e/rbac.yaml. Because the current user doesn't have permission to restart node 10.205.13.241, Kubernetes permission verification was not passed here.
