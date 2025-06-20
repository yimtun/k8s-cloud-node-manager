# 在开启了OIDC的EKS集群内运行


- EKS开启OIDC支持后Pod中运行的k8s-cloud-node-manager可以通过ServiceAccount来访问 AWS API，这也是AWS 推荐的访问方式

- 在本文档内容中，运行shell命令的工作路径是工程目录下的docs，在编辑本文档时验证命令的时候使用的ide可以识别md文件中的shell命令，可以在md中点击直接运行会自动创建一个终端并执行命令，所以基本每条命令开始前都会有一个切换路径cd命令

- 前置条件： 安装并配置好awscli 安装好terraform 


## 使用示例terraform创建支持OIDC的eks集群


```shell
cd ../examples/oidc_eks_tf/
terraform apply
```

在tf中已经设置好了rbac  所以后面不再需要执行 deploy/inCluster/rbac.yaml


## 获取eks的kubeconfig文件

```shell
cd ..
aws eks update-kubeconfig --name my-eks-cluster --region us-east-1 --kubeconfig ./config-eks
```


## 生成证书

```shell
cd ../hack
sh gen.sh
```


**将文件certs/caBundle.txt 中的内容复制到 文件 deploy/apiservice.yaml  caBundle中**




## 创建 secert 用于存储tls证书

```shell
cd ..
kubectl --kubeconfig ./config-eks delete secret extended-api-tls -n default
kubectl --kubeconfig ./config-eks create secret tls extended-api-tls --cert=./certs/tls.crt --key=./certs/tls.key -n default
```



**虽然是单一的 aws 集群 这里还是选择创建一个空的 tencentcloud-credentials 避免secretKeyRef报错**

```shell
cd ..
kubectl --kubeconfig ./config-eks delete secret tencentcloud-credentials -n default
kubectl --kubeconfig ./config-eks create secret generic tencentcloud-credentials \
  --from-literal=TENCENTCLOUD_SECRET_ID="xxxx" \
  --from-literal=TENCENTCLOUD_SECRET_KEY="xxxx" \
  -n default
```


## 执行清单文件

使用eks的OIDC 所以需要执行 eks_oidc_deployment.yaml

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


##  查看 apiservice 状态


```shell
cd ..
kubectl --kubeconfig ./config-eks   get apiservice v1.infraops.michael.io
```

输出展示：

```text
NAME                     SERVICE                    AVAILABLE   AGE
v1.infraops.michael.io   default/infraops-service   True        36s
```


## 查看接口文档

```shell
cd ..
kubectl --kubeconfig ./config-eks get --raw   "/apis/infraops.michael.io/v1" | jq .
```

输出展示：

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

**当前使用的核心资源nodes所以上面输出json文件中的nodes资源相关接口并没有实现**



##  测试



下面的两种测试方法 可以展示 这里的AA  本质上还是是一个普通http的接口

 



###  curl 命令测试接口

从config-eks 中获取ca

```shell
cd ..
export KUBECONFIG=./config-eks
CURRENT_CONTEXT=$(kubectl  config view --raw -o jsonpath='{.current-context}')
CLUSTER_NAME=$(kubectl     config view --raw -o jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.cluster}")
USER_NAME=$(kubectl        config view --raw -o jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.user}")
kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority-data}" | base64 -d > /tmp/ca.crt
```

获取token

```shell
aws eks get-token --cluster-name my-eks-cluster  --region us-east-1 | jq -r '.status.token'  > /tmp/token
```

获取k8s api 端点

```shell
cd ..
export KUBECONFIG=./config-eks
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
```

输出展示：

```shell
https://DA9C70C8535A5ADDE9C74C3600756B25.gr7.us-east-1.eks.amazonaws.com
```



curl 测试命令

```shell
curl -X POST \
  --cacert /tmp/ca.crt \
  -H "Authorization: Bearer $(cat /tmp/token)" \
  "https://DA9C70C8535A5ADDE9C74C3600756B25.gr7.us-east-1.eks.amazonaws.com/apis/infraops.michael.io/v1/nodes/testNODE/restart"
```

输出展示：

```text
Failed to get node testNODE: nodes "testNODE" not found
```
这个调用是正常的 因为确实没有这个node 


###  kubectl  plugin 方式测试

安装kubeclt plugin

```shell
go build  -o /usr/local/bin/kubectl-restart ../kubectlplugins/kubectl-restart.go
```



```shell
cd ..
kubectl --kubeconfig ./config-eks get node
```

输出展示：

```text
kubectl --kubeconfig ./config-eks get node
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-10-98.ec2.internal    Ready    <none>   12m   v1.32.3-eks-473151a
ip-10-0-11-190.ec2.internal   Ready    <none>   12m   v1.32.3-eks-473151a
```

这里可以看出 这里使用的数据源实际上就是 k8s 核心资源nodes 



重启node


```shell
cd ..
export KUBECONFIG=./config-eks
kubectl  restart ip-10-0-11-190.ec2.internal
```

输出展示：

```text
使用 exec 认证: aws [--region us-east-1 eks get-token --cluster-name my-eks-cluster]
请求失败，状态码: 500，响应: you can't rebootip-10-0-11-190.ec2.internalbecause I run on it
```

k8s-cloud-node-manager 使用 Downward API 判断出来 k8s-cloud-node-manager这个pod 正运行在节点 ip-10-0-11-190.ec2.internal上  所以终止了重启nodede 自杀行为

我们可以确认下

```shell
cd ..
export KUBECONFIG=./config-eks
kubectl  get pod -o wide
```

输出展示：

```text
NAME                                   READY   STATUS    RESTARTS   AGE   IP            NODE                          NOMINATED NODE   READINESS GATES
extended-api-server-566b9954b7-8bv9l   1/1     Running   0          12m   10.0.11.206   ip-10-0-11-190.ec2.internal   <none>           <none>
```

再来重启另一个node

```shell
cd ..
export KUBECONFIG=./config-eks
kubectl  restart ip-10-0-10-98.ec2.internal
```

输出展示：

```text
使用 exec 认证: aws [--region us-east-1 eks get-token --cluster-name my-eks-cluster]
Node ip-10-0-10-98.ec2.internal (providerID: aws:///us-east-1a/i-0da7c9af35266791d, 实例ID: i-0da7c9af35266791d, 云厂商: AWS) 已重启
```

等服务器重启完 课登录服务器验证

```shell
aws ssm start-session --target  i-0da7c9af35266791d    --region=us-east-1 
```


## 销毁测试eks集群

```shell
cd ../examples/oidc_eks_tf/
terraform destroy
```