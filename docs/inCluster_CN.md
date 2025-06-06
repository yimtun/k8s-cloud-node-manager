# 在自建的k8s集群内部署myapiserver


- 前置条件： 当前已经有一个可用的k8s集群且已经配置好kubecofig 位于默认路径 $HOME/.kube/config



## 生成证书

```shell
cd ../hack
sh gen.sh
```

**将文件certs/caBundle.txt 中的内容复制到 文件 deploy/apiservice.yaml  caBundle中**


## 创建 secert 用于存储tls证书

```shell
cd ..
kubectl   delete secret extended-api-tls -n default
kubectl   create secret tls extended-api-tls --cert=./certs/tls.crt --key=./certs/tls.key -n default
```


##  创建用于调用云接口的 credentials

```shell
kubectl  delete secret tencentcloud-credentials -n default
kubectl  create secret generic tencentcloud-credentials \
  --from-literal=TENCENTCLOUD_SECRET_ID="xxxx" \
  --from-literal=TENCENTCLOUD_SECRET_KEY="xxxx" \
  -n default
```


```shell
kubectl delete secret aws-credentials -n default
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID="xxxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxxx" \
  -n default
```



## 执行清单文件


```shell
kubectl  apply -f ../deploy/inCluster/rbac.yaml
kubectl  apply -f ../deploy/inCluster/service.yaml
kubectl  apply -f ../deploy/inCluster/deployment.yaml
kubectl  apply -f ../deploy/apiservice.yaml
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



## 测试


### 设置mock

当前的k8s集群实际上并没有使用到 aws 和 腾讯云的 服务器作为node节点 通过patch node 设置providerID 的方式可以进行功能测试

```shell
kubectl patch node dev -p  '{"spec":{"providerID":"qcloud:///800000/ins-lxaytb49"}}'
kubectl patch node dev1 -p '{"spec":{"providerID":"aws:///us-east-1a/i-0da7c9af35266791d}}'
```



### curl 调用 apiserer 入口进行测试

- 从$HOME/.kube/config 中提取通用证书文件

```shell
sh  ../hack/get_certs_from_kubeconfig.sh
```

k8s 接口地址  10.211.55.18:6443

```bash
curl -X POST   \
--cacert /tmp/ca.crt   \
--cert /tmp/client.crt   \
--key /tmp/client.key  \
 "https://10.211.55.18:6443/apis/infraops.michael.io/v1/nodes/dev/restart"
```


###  kubectl  plugin 方式测试

安装kubeclt plugin

```shell
go build  -o /usr/local/bin/kubectl-restart ../kubectlplugins/kubectl-restart.go
```


```shell
kubectl get  node
```


- 插件默认使用kubeconfig 的路径就是 $HOME/.kube/config

```shell
kubectl restart dev
```

