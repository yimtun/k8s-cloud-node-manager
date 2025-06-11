# k8s-cloud-node-manager

[🇺🇸 Switch to English English Version](README.md)

> **通过API Aggregation (AA)机制扩展Kubernetes，用于将Kubernetes相关的云服务器管理工作统一在Kubernetes接口中 展现了一种无需注册资源的轻量化的实现**

**项目特性：**
- 支持在单一 Kubernetes 集群内，对接和管理来自 AWS、腾讯云等不同云厂商的节点（关于这种架构下涉及到的高性能通用cni会在另一个项目中实现），实现多云节点的统一运维和操作。
- 对于云厂商托管的 Kubernetes 集群（如 AWS EKS、腾讯云 TKE），本项目可原生支持。
- 通过各云厂商托管集群的node ProviderID格式自动识别云厂商类型和获取云服务器id，自建集群需保证ProviderID格式同对应云厂商一致，自建时可手动设置或借助其他工具实现。
- 没有使用框架和底层库实现，比如 apiserver-builder-alpha 和 k8s.io/code-generator 展示了一个不同的使用方式 即 不注册AA资源到k8s   仅通过 API Aggregation （AA） 机制暴露了标准 Kubernetes 风格的 API 端点 来实现业务需求 是一种轻量化的实现
- 将对云node节点的云服务器的操作统一接入到Kubernetes标准接口 可利用Kubernetes rabc 控制云服务器资源操作权限 比如开发人员不必拥有云厂商帐号就可以操作开发画家的 node节点
- 可应用于混沌工程，通过AA扩展的接口，所用到的数据源就是当前集群的核心资源nodes 不易出现错误。
- 部署方式安全严格 涉及自签证书的使用 强制验证ca等
---

## 概述

k8s-cloud-node-manager 是一个基于 Kubernetes API Server Aggregation（AA）机制实现的 API 扩展。  
与 CustomResourceDefinition（CRD）不同，CRD 是声明式的，由 Kubernetes 控制平面处理，而 AA 允许我们部署独立的 API 服务器来为自定义资源提供专门的实现。主 API 服务器将自定义 API 的请求委托给这个扩展服务器，使其对所有客户端可用。这种方式使我们能够实现复杂的业务逻辑（如调用云服务商 API 重启节点），同时保持 Kubernetes API 标准。支持集群内和集群外两种部署方式，并提供 kubectl 插件以方便节点操作。  
下文将介绍 Kubernetes 扩展的主要方式及本项目的选型理由。

---

## Kubernetes API 扩展方式与选型

官方文档在扩展开发表达方面略显混乱，以下结合实际经验进行梳理和总结。

通过创建custom resource的方式扩展 Kubernetes API



### 创建Kubernetes custom resource 的途径

Kubernetes 提供两种方式向集群添加custom resource

- **CustomResourceDefinition（CRD）**
- **API 聚合（API Aggregation，AA）**

> 参考：[Kubernetes API 扩展方式](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/)



### CRD和AA实际使用场景的总结

实际开发中，**CRD 和 AA 可以根据业务需求灵活组合**，二者并不是二选一的关系。常见的几种模式如下：

1. **只有 CRD**  
   只声明资源类型，不处理数据，**实际很少这样用**，除非只是为了存储信息。

2. **CRD + Custom Controller**  
   **最常见的 Operator 模式**，即“声明资源 + 自动化管理”，是 Operator 的标准实现方式 有大量开源项目和社区资料。

3. **只有AA接口 不注册AA资源**
   不向Kubernetes注册AA资源，仅暴露标准 Kubernetes API 风格的端点。
   AA类型的custom resource不需要注册资源到Kubernetes 直接通过 API 聚合扩展 API，**适合需要被那管到k8s场景的自定义API行为的场景**，本项目采用的方式。

4. **AA + Custom Controller**  
   custom resource 需要注册到Kubernetes 也是Operator 模式 比如示例项目kubernetes/staging/src/k8s.io/sample-apiserver

5. **CRD + Custom Controller + AA**
   比如kubevirt 适合复杂业务场景，既需要声明资源、自动化管理，又需要自定义 API 行为（如聚合、跨资源操作等）。这种模式可以看作是**高阶的 Operator 实现**。

### 本项目选型理由

本项目采用了仅使用 AA 的模式，主要基于以下考虑：

1. **动作型子资源支持**
   本项目的 restart 是一个动作型子资源，类似于 Kubernetes 内置的 log、exec 等。这类子资源只能通过 AA 实现，CRD 仅支持 status 和 scale 两种内置子资源，无法满足需求。

2. **命令式接口需求**
    本项目需要实现命令式（imperative）接口，如 `/restart`，用于直接触发节点重启操作。这类接口不属于 Kubernetes 传统的声明式 API，无法通过 CRD 直接实现，而 AA 机制则为此类操作提供了灵活的支持。

3. **无需 Controller 监听和调和（watch 和 reconcile）** 
    本项目不需要注册AA资源（`apis/infraops.michael.io/v1/nodes`） ，实际上数据源是复用的核心资源资源(`/api/v1/nodes`) 也不需要watch和reconcile其他资源，也就不需要Custom Controller，因此无需采用 AA + Custom Controller 的模式。
    在用户角度看 就像是为核心资源添加了一个子资源restart :  `kubectl restart nodeName`

---

## 特性

- **多云支持：** 管理AWS、腾讯云云上的节点。
- **Kubernetes API 扩展：** 提供 `/apis/infraops.michael.io/v1` 端点。
- **节点重启 API：** 通过标准 Kubernetes API 或 kubectl 插件重启节点。
- **灵活部署：** 支持集群内和集群外两种模式。
- **安全通信：** 使用 HTTPS 和 Kubernetes RBAC。

---


## 快速开始

### 前置准备



1. **生成证书**


```bash
cd hack
sh gen.sh
```
- 如需修改 IP/命名空间，请编辑 `hack/gen.sh` 用你自定义的namespace 替换 default即可。
- 如果使用 ExternalName Service 让 k8s-cloud-node-manager在Kubernetes集群外运行，生成证书前请修改hack/gen.sh脚本确保签发证书时 设置正确的subjectAltName 以当前示例 替换IP:10.211.55.2 内容即可
- 脚本会在 `certs/` 目录生成证书，并生成文件 `certs/caBundle.txt` 该文件内容用于填充 deploy/apiservice.yaml 文件的caBundle 生成证书后请务必配置好该文件


如果将k8s-cloud-node-manager部署在Kubernetes内,需要创建tls secret供pod内程序启动时加载

```shell
kubectl create secret tls extended-api-tls --cert=certs/tls.crt --key=certs/tls.key -n default
```


2. **创建secret存储云服务商凭证**


针对运行在Kubernetes集群内的情况 需要在Kubernetes上配置云厂商接口调用凭证 secret 分为下面几种场景：


- 如果是集群是tke 或者 在腾讯云上的自建 Kubernetes集群        属于单一云环境  仅需配置  secret  tencentcloud-credentials

- 如果是集群是 没有开启OIDC的eks或者在aws上自建Kubernetes集群  属于单一云环境  仅需配置  secret  aws-credentials

- 如果集群是开启了 OIDC的eks 属于单一云环境 但是无需配置 secret  aws-credentials

- 如果是自建的集群 且 同时使用了 腾讯云和aws上的云服务器作为 node 节点  属于多云环境 需要同时配置 secret aws-credentials 和 tencentcloud-credentials


配置  secret  credentials 的命令

腾讯云
```shell
kubectl create secret generic tencentcloud-credentials \
     --from-literal=TENCENTCLOUD_SECRET_ID=xxx \
     --from-literal=TENCENTCLOUD_SECRET_KEY=xxx -n default
```

aws
```shell
kubectl delete secret aws-credentials -n default
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID="xxxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxxx" \
  -n default
```


你可以用下面的命令获取你的 aws keyid 和 accesskey
```shell
cat  ~/.aws/credentials
```


./config-eks 是一个eks 的 kubeconfig 文件 使用如下命令生成的：

```shell
aws eks update-kubeconfig --name my-eks-cluster --region us-east-1 --kubeconfig ./config-eks
```

注意: 在单云场景下在k8s集群内部运行的情况 可根据情况删减文件deploy/inCluster/deployment.yaml deploy/inCluster/eks_oidc_deployment.yaml
中的env配置 以避免secretKeyRef 中的 secret 不存在时的报错  当然也可以不修改，直接创建一个对应名字的空的secret。




### 部署方式选择

- 除了OIDC的EKS不支持集群外部署，其他的场景都支持集群外和集群内两种部署方式。
- 除非用于开发调试 在所有环境下都推荐集群内部署

综合上述观点 本项目现提供下面几种环境下的部署文档：

1. **在自建的集群内部署**
    - 适用于自建 Kubernetes 集群
    - 适用于多云环境
    - [详细部署指南](docs/inCluster_CN.md)

2. **在开启OIDC的EKS集群内部署**
    - 支持 EKS OIDC 认证
    - 适用于 AWS 托管集群 单云环境
    - [详细部署指南](docs/eks_inCluster_OIDC_CN.md)
   
3. **在未开启OIDC的EKS集群内部署**
    - 适用于 AWS 托管集群 单云环境
    - [详细部署指南](docs/eks_inCluster_CN.md)

4. **在TKE集群内部署**
    - 适用于 TKE 托管集群 单云环境
    - [详细部署指南](docs/tke_inCluster_CN.md)

5. **在集群外部署（开发环境）**
    - 适用于自建 Kubernetes 集群
    - 适用于开发和调试
    - 支持本地运行
    - 适用于多云环境
    - [详细部署指南](docs/out-of-band-deployment.md)

### 验证部署
1. 检查 API Service 状态

查看  AA 是否可用

```shell
kubectl  get apiservice v1.infraops.michael.io
```

输出：
```text
NAME                     SERVICE                    AVAILABLE   AGE
v1.infraops.michael.io   default/infraops-service   True        18m
```


查看接口文档

```shell
kubectl get --raw "/apis/infraops.michael.io/v1" | jq .
```



---

## API 使用

### curl 调用


需要确定certs ??

- 重启节点： 
  ```bash
  curl -X POST \
    --cacert ./certs/ca.crt \ 
    --cert ./certs/tls.crt \
    --key  ./certs/tls.key \
    "https://<apiserver-ip>:/apis/infraops.michael.io/v1/nodes/<nodename>/restart"
  ```


---

### kubectl 调用

- 构建和安装 kubectl plugin：
  ```bash
  go build -o /usr/local/bin/kubectl-restart kubectlplugins/kubectl-restart.go
  ```
- 使用方法：

获取 node 节点

  ```bash
  kubectl get node
  ```

选择一个node 测试重启

  ```bash
  kubectl restart <nodename>
  ```

## 测试 借助Kubernetes的权限系统 保护接口

创建一个受限的 Kubernetes 用户

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

输出：

```text
使用 Token 认证
请求失败，状态码: 500，响应: Failed to get node 10.205.13.240: nodes "10.205.13.240" not found
```

这个输出是符合 e2e/rbac.yaml 定义的  虽然当前没有找到node  但实际上这已经通过了Kubernetes的权限校验



```sehll
kubectl   restart  10.205.13.241
```

输出:

```text
使用 Token 认证
请求失败，状态码: 403，响应: {"kind":"Status","apiVersion":"v1","metadata":{},"status":"Failure","message":"nodes.infraops.michael.io \"10.205.13.24idden: User \"system:serviceaccount:default:node-restarter\" cannot create resource \"nodes/restart\" in API group \"infraops.michael.io\" at the cluster scope","reason":"Forbidden","details":{"name":"10.205.13.241","group":"infraops.michael.io","kind":"nodes"},"code":403}
```

这个输出是符合 e2e/rbac.yaml 定义的  因为当前用户没有权限去 restart 节点 10.205.13.241 这里就没有通过Kubernetes的权限校验
