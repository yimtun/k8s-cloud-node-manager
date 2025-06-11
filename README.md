# myapiserer

[🇨🇳 切换到中文版本](README_CN.md)

> **Kubernetes Extended API Server for Node Management in Multi-Cloud Environments**

**Project Features:**
- Supports managing nodes from different cloud providers (AWS, Tencent Cloud, etc.) within a single Kubernetes cluster (a high-performance universal CNI for this architecture will be implemented in another project), enabling unified operations and maintenance of multi-cloud nodes.
- Native support for cloud provider-managed Kubernetes clusters (such as AWS EKS, Tencent Cloud TKE).
- Automatically identifies cloud provider types and retrieves cloud server IDs through the node ProviderID format of each cloud provider's managed cluster. For self-built clusters, ensure the ProviderID format matches the corresponding cloud provider, which can be set manually or implemented using other tools.
- Implemented without using frameworks or underlying libraries like apiserver-builder-alpha and k8s.io/code-generator, demonstrating a different approach by not registering AA resources to k8s, only exposing standard Kubernetes-style API endpoints through the API Aggregation (AA) mechanism to meet business requirements, resulting in a lightweight implementation.
- Unifies cloud server operations for cloud node nodes into standard Kubernetes interfaces, leveraging Kubernetes RBAC to control cloud server resource operation permissions, allowing developers to operate cloud nodes without needing cloud provider accounts.
- Applicable to chaos engineering, using the current cluster's core resources (nodes) as the data source through AA-extended interfaces, minimizing errors.
- Secure and strict deployment approach, involving the use of self-signed certificates and mandatory CA verification.

---

## Overview

myapiserer is an API extension implemented based on the Kubernetes API Server Aggregation (AA) mechanism.  
Unlike CustomResourceDefinition (CRD), which is declarative and handled by the Kubernetes control plane, AA allows us to deploy independent API servers to provide specialized implementations for custom resources. The main API server delegates requests for custom APIs to this extension server, making them available to all clients. This approach enables us to implement complex business logic (such as calling cloud provider APIs to restart nodes) while maintaining Kubernetes API standards. It supports both in-cluster and out-of-cluster deployment methods and provides a kubectl plugin for convenient node operations.  
The following sections will introduce the main methods of Kubernetes extension and the rationale behind this project's approach.

---

## Kubernetes API Extension Methods and Selection

The official documentation is somewhat confusing in terms of extension development. The following is a practical summary based on experience.

### Ways to Create Kubernetes Custom Resources

Kubernetes provides two ways to add custom resources to a cluster:

- **CustomResourceDefinition (CRD)**
- **API Aggregation (AA)**

> Reference: [Kubernetes API Extension Methods](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/)

### Summary of CRD and AA Practical Use Cases

In actual development, **CRD and AA can be flexibly combined based on business requirements**; they are not mutually exclusive. Common patterns include:

1. **CRD Only**  
   Only declares resource types without processing data, **rarely used this way** unless just for storing information.

2. **CRD + Custom Controller**  
   **The most common Operator pattern**, i.e., "declare resources + automated management", is the standard implementation of Operators with numerous open-source projects and community resources.

3. **AA Interface Only, No AA Resource Registration**  
   Does not register AA resources to Kubernetes, only exposes standard Kubernetes API-style endpoints.
   AA-type custom resources don't need to be registered to Kubernetes, directly extending APIs through API aggregation, **suitable for scenarios requiring custom API behavior managed by k8s**. This is the approach adopted by this project.

4. **AA + Custom Controller**  
   Custom resources need to be registered to Kubernetes, also an Operator pattern, e.g., the sample project kubernetes/staging/src/k8s.io/sample-apiserver.

5. **CRD + Custom Controller + AA**  
   Like kubevirt, suitable for complex business scenarios requiring resource declaration, automated management, and custom API behavior (such as aggregation, cross-resource operations, etc.). This pattern can be seen as an **advanced Operator implementation**.

### Project Selection Rationale

This project adopts the AA-only mode, mainly based on the following considerations:

1. **Action Subresource Support**  
   The restart feature in this project is an action subresource, similar to Kubernetes built-in log, exec, etc. Such subresources can only be implemented through AA; CRD only supports status and scale as built-in subresources, which cannot meet the requirements.

2. **Imperative Interface Requirements**  
   This project needs to implement imperative interfaces like `/restart` for directly triggering node restart operations. Such interfaces don't belong to Kubernetes traditional declarative APIs and cannot be directly implemented through CRD, while the AA mechanism provides flexible support for such operations.

3. **No Need for Controller Watch and Reconcile**  
   This project doesn't need to register AA resources (`apis/infraops.michael.io/v1/nodes`); in fact, the data source reuses core resources (`/api/v1/nodes`). It also doesn't need to watch and reconcile other resources, so no Custom Controller is needed, thus eliminating the need for the AA + Custom Controller pattern.
   From the user's perspective, it's like adding a restart subresource to core resources: `kubectl restart nodeName`

---

## Features

- **Multi-Cloud Support:** Manage nodes on AWS, Tencent Cloud, etc.
- **Kubernetes API Extension:** Provides `/apis/infraops.michael.io/v1` endpoint.
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
- To modify IP/namespace, edit `hack/gen.sh` and replace default with your custom namespace.
- If using ExternalName Service to run myapiserver outside the Kubernetes cluster, modify the hack/gen.sh script before generating certificates to ensure correct subjectAltName is set. For the current example, replace IP:10.211.55.2 content.
- The script will generate certificates in the `certs/` directory and create file `certs/caBundle.txt`, whose content is used to fill the caBundle in deploy/apiservice.yaml. Please ensure this file is properly configured after generating certificates.

If deploying myapiserver inside Kubernetes, create a tls secret for the pod to load when starting:

```shell
kubectl create secret tls extended-api-tls --cert=certs/tls.crt --key=certs/tls.key -n default
```

2. **Create Secret for Cloud Provider Credentials**

For scenarios running inside a Kubernetes cluster, configure cloud provider API call credentials in Kubernetes. The secret scenarios are as follows:

- If the cluster is TKE or a self-built Kubernetes cluster on Tencent Cloud (single cloud environment), only configure secret tencentcloud-credentials.

- If the cluster is EKS without OIDC or a self-built Kubernetes cluster on AWS (single cloud environment), only configure secret aws-credentials.

- If the cluster is EKS with OIDC enabled (single cloud environment), no need to configure secret aws-credentials.

- If it's a self-built cluster using both Tencent Cloud and AWS cloud servers as node nodes (multi-cloud environment), configure both secrets aws-credentials and tencentcloud-credentials.

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

You can get your AWS keyid and accesskey using:
```shell
cat  ~/.aws/credentials
```

./config-eks is an EKS kubeconfig file generated using:

```shell
aws eks update-kubeconfig --name my-eks-cluster --region us-east-1 --kubeconfig ./config-eks
```

Note: In single-cloud scenarios running inside a k8s cluster, you can modify the env configuration in files deploy/inCluster/deployment.yaml and deploy/inCluster/eks_oidc_deployment.yaml to avoid errors when the secret referenced by secretKeyRef doesn't exist. Alternatively, you can create an empty secret with the corresponding name.

### Deployment Options

- Except for EKS with OIDC, all other scenarios support both in-cluster and out-of-cluster deployment.
- Unless for development and debugging, in-cluster deployment is recommended for all environments.

Based on the above, this project now provides deployment documentation for the following environments:

1. **Deploy in Self-built Cluster**
    - Suitable for self-built Kubernetes clusters
    - Suitable for multi-cloud environments
    - [Detailed Deployment Guide](docs/inCluster_CN.md)

2. **Deploy in EKS Cluster with OIDC Enabled**
    - Supports EKS OIDC authentication
    - Suitable for AWS managed clusters, single cloud environment
    - [Detailed Deployment Guide](docs/eks_inCluster_OIDC_CN.md)
   
3. **Deploy in EKS Cluster without OIDC**
    - Suitable for AWS managed clusters, single cloud environment
    - [Detailed Deployment Guide](docs/eks_inCluster_CN.md)

4. **Deploy in TKE Cluster**
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
kubectl get apiservice v1.infraops.michael.io
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

[View Complete Deployment Documentation](docs/quick-start.md)

---

## API Usage

### curl Calls

Need to determine certs ??

- Restart Node: 
  ```bash
  curl -X POST \
    --cacert  /tmp/ca.crt \ 
    --cert    /tmp//tls.crt \
    --key     /tmp//tls.key \
    "https://<apiserver-ip>:/apis/infraops.michael.io/v1/nodes/<nodename>/restart"

