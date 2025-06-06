#  在k8s集群外 部署myapiserver

**用于调试开发环境使用**

- 前置条件： 当前已经有一个可用的k8s集群且已经配置好kubecofig 位于默认路径 $HOME/.kube/config

---
## 生成证书

- 修改下证书脚本文件：hack/gen.sh
在集群外运行时使用的是ExternalName类型的Service所以需要确保 subjectAltName 匹配
在当前的案例 脚本中的IP:10.211.55.2部分， 10.211.55.2 是在k8s集群角度看myapiserver运行的ip 所以这里的ip 或域名不必是你运行myapiserver的真实ip 或域名 也可以是代理后的ip或域名

  
```shell
cd ../hack
sh gen.sh
```

**将文件certs/caBundle.txt 中的内容复制到 文件 deploy/apiservice.yaml  caBundle中**

---
## 修改deploy/outCluster/service.yaml 

- 需要设置一个ExternalName Service 将你本地运行的myapiserver 暴露给 Kubernetes apiserver 不一定是myapiser的实际运行ip和端口 也可以是经过代理后的入口 只要证书和入口的域名匹配和网络可达即可

```yaml
apiVersion: v1
kind: Service
metadata:
  name:  infraops-service
  namespace: default
spec:
  type: ExternalName
  externalName: 10.211.55.2   # myapiserver run ip 
  ports:
    - port: 443               # myapiserver run port 
      protocol: TCP
```


## 为myapiserver设置独立的serviceaccount

- 避免运行myapiserver使用管理员权限的kubeconfig 文件所以为其配置独立的kubeconfig 文件


```shell
kubectl apply  -f ../deploy/outCluster/rbac.yaml 
```


```shell
cd ..
sh  ./hack/hackget_kubeconfig_from_token.sh  default  extended-api-server-token
```


## 执行清单文件


```shell
kubectl apply -f deploy/apiservice.yaml
kubectl apply -f deploy/outCluster/service.yaml
```



## 运行myapiserver


- 设置mock

当前的k8s集群实际上并没有使用到 aws 和 腾讯云的 服务器作为node节点 通过patch node 设置providerID 的方式可以进行功能测试


```shell
kubectl patch node dev -p  '{"spec":{"providerID":"qcloud:///800000/ins-lxaytb49"}}'
kubectl patch node dev1 -p '{"spec":{"providerID":"aws:///us-east-1a/i-0da7c9af35266791d}}'
```





- 设置环境变量 用于调用云接口凭证

```shell
export TENCENTCLOUD_SECRET_ID="xxx"
export TENCENTCLOUD_SECRET_KEY="xxx"
export TENCENTCLOUD_REGION="xxx"

export  AWS_ACCESS_KEY_ID="xxxx"
export  AWS_SECRET_ACCESS_KEY="xxxx" 
export  AWS_REGION="xxxx"
```



如果不指定 kubeconfig 会使用当前用户加目录下的  .kube/config 文件

- 指定kubeconfig 运行myapiserer 


```shell
cd ..
go run apiserver.go  --kubeconfig extended-api-server-kubeconfig
```



##  查看 apiservice 状态


```shell
kubectl get apiservice v1.infraops.michael.io
```


```text
NAME                     SERVICE                    AVAILABLE   AGE
v1.infraops.michael.io   default/infraops-service   True        129m
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


###  curl 直接调用本地接口 

- hack/gen.sh 中需要设置 subjectAltName 相关设置 IP:127.0.0.1

```bash
curl -X POST   \
--cacert ../certs/ca.crt   \
--cert ../certs/tls.crt   \
--key  ../certs/tls.key  \
 "https://127.0.0.1:/apis/infraops.michael.io/v1/nodes/xxnode/restart"
```


### curl 调用ExternalName Service 的入口测试


- hack/gen.sh 中需要设置 subjectAltName 相关设置 IP:10.211.55.2
- 本例中 就是deploy/outCluster/service.yaml 文件中的ip 和端口 （10.211.55.2 443） 因为443 是https 默认端口 调用时端口和省略


```bash
curl -X POST   \
--cacert ../certs/ca.crt   \
--cert   ../certs/tls.crt   \
--key    ../certs/tls.key  \
 "https://10.211.55.2:443/apis/infraops.michael.io/v1/nodes/xxnode/restart"
```


#### curl 调用 apiserer 入口进行测试

- 从$HOME/.kube/config 中提取通用证书文件

```shell
sh  ../hack/get_certs_from_kubeconfig.sh
```


```bash
curl -X POST   \
--cacert /tmp/ca.crt   \
--cert /tmp/client.crt   \
--key /tmp/client.key  \
 "https://10.211.55.18:6443/apis/infraops.michael.io/v1/nodes/dev/restart"
```

- https://10.211.55.18:6443 是apiserver 的入口




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
