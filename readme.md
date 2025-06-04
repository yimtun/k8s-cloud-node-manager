# kubernetes Extension API Server (extension-apiserver)

https://v1-32.docs.kubernetes.io/docs/concepts/extend-kubernetes/api-extension/apiserver-aggregation/


## 部署  apiservice 后查看

```shell
kubectl  get apiservice v1.infraops.michael.io
NAME                     SERVICE                    AVAILABLE   AGE
v1.infraops.michael.io   default/infraops-service   True        18m
```

## 获取 自定义api组 信息


查看核心API 

```shell
kubectl get --raw /openapi/v2 | jq '.paths | keys'
```


查看 自己写的扩展api 

```shell
kubectl get --raw   "/apis/infraops.michael.io/v1" | jq .
```


# 部署

## 生成证书

修改下证书脚本

```bash
vim hack/gen.sh
IP:10.211.55.2   #将2处 10.211.55.2 替换为 在集群外运行时 服务运行的时间ip 即可
```

```shell
cd hack
sh gen.sh
```

会生成一个文件 用于 apiservice 的 caBundle 填值
certs/caBundle.txt


## 集群外部署 

用于调试开发环境使用

### 修改配置文件


deploy/outCluster/outOfCluster.yaml

```yaml
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1.infraops.michael.io
spec:
  version: v1
  group: infraops.michael.io
  groupPriorityMinimum: 2000
  service:
    name: infraops-service
    namespace: default
  versionPriority: 10
  caBundle: 替换为 certs/caBundle.txt 里面的内容
---
apiVersion: v1
kind: Service
metadata:
  name:  infraops-service
  namespace: default
spec:
  type: ExternalName
  externalName: 10.211.55.2   # 修改为扩展server 运行的地址
  ports:
    - port: 443               # 修改扩展server 运行的端口
      protocol: TCP
```


```bash
kubectl apply -f deploy/outCluster/outOfCluster.yaml
```


### 为扩展server 创建 k8s 账户 并设置权限

修改 namesapce 
```yaml
vim deploy/outCluster/rbac.yaml 
```

```bash
kubectl apply   -f deploy/outCluster/rbac.yaml 
```

生成 kubeconfig 文件 文件路径 extended-api-server-kubeconfig

```bash
cd hack
sh get_kubeconfig_from_token.sh  default extended-api-server-token
```

加载 云接口认证信息  启动apiserver 

```bash
export TENCENTCLOUD_SECRET_ID="xxx"
export TENCENTCLOUD_SECRET_KEY="xxx"
export TENCENTCLOUD_REGION="ap-guigu"
```


如果不值当 kubeconfig 会使用当前用户加目录下的  .kube/config 文件
```
go run apiserver.go  --kubeconfig extended-api-server-kubeconfig
```

查看apiservice

```bash
kubectl get apiservice v1.infraops.michael.io
```

```text
NAME                     SERVICE                    AVAILABLE   AGE
v1.infraops.michael.io   default/infraops-service   True        129m
```


### 接口验证


####  直接验证接口

ip 地址需要是签名扩展中 填的ip 

```bash
curl -X POST   \
--cacert ./certs/ca.crt   \
--cert ./certs/tls.crt   \
--key  ./certs/tls.key  \
 "https://127.0.0.1:/apis/infraops.michael.io/v1/nodes/xxnode/restart"
```

从注册到 k8s service 的 入口测试



```bash
curl -X POST   \
--cacert ./certs/ca.crt   \
--cert ./certs/tls.crt   \
--key  ./certs/tls.key  \
 "https://10.211.55.2:/apis/infraops.michael.io/v1/nodes/xxnode/restart"
```


#### 从k8s 的 接口验证



```bash
cd hack
sh  get_certs_from_kubeconfig.sh
```

从 k8s 接口地址  10.211.55.18:6443

```bash
curl -X POST   \
--cacert /tmp/ca.crt   \
--cert /tmp/client.crt   \
--key /tmp/client.key  \
 "https://10.211.55.18:6443/apis/infraops.michael.io/v1/nodes/dev/restart"
```


测试 go 版本的 kubectl plugin

```shell
go build  -o /usr/local/bin/kubectl-restart kubectlplugins/kubectl-restart.go
```


```shell
kubectl get  node
```

```shell
kubectl restart dev
```








## 如果运行方式 是 inCluster  

创建secret 存储证书

```shell
cd certs/
kubectl create secret tls extended-api-tls --cert=tls.crt --key=tls.key -n default
```



test api from. k8s api


get certs from kubecofnig

```shell
sh client-certs/get-cert.sh
```


## kubectl plugin test

```shell
export PATH=$PATH:/Users/yandun/github.com/myapiserer/kubectlplugins
```


```shell
kubectl restart default test-vm
VMI test-vm has been restartedyandundeMacBook-Pro:myapiserer yandun$ 
```


## restart cloud vm node

```shell
curl -X POST   \
--cacert /tmp/ca.crt   \
--cert /tmp/client.crt   \
--key /tmp/client.key  \
 "https://10.211.55.18:6443/apis/infraops.michael.io/v1/nodes/dev/restart"
```

outOfCluster test


### for mock 

```shell
kubectl patch node dev -p '{"spec":{"providerID":"qcloud:///800006/ins-lxaytb49"}}'
```
```shell
get node dev -o json | jq '.spec.providerID'
```

```
"qcloud:///800006/ins-lxaytb49"
```



tencent

```shell
export TENCENTCLOUD_SECRET_ID="xxx"
export TENCENTCLOUD_SECRET_KEY="xxx"
export TENCENTCLOUD_REGION="ap-guigu"
```

curl test tencent cloud

```shell
cvm.internal.tencentcloudapi.com
```


## run inCluster 

```
kubectl create secret generic tencentcloud-credentials \
  --from-literal=TENCENTCLOUD_SECRET_ID="xxxx" \
  --from-literal=TENCENTCLOUD_SECRET_KEY="xxxx" \
  -n default
```

# run in cluster

##  create tls certs

### gen certs

```shell
cd ./hack
bash gen.sh
cd ..
```


```shell
cd ./certs
kubectl delete secret extended-api-tls -n default
kubectl create secret tls extended-api-tls --cert=tls.crt --key=tls.key -n default
cd ..
```

```shell
kubectl create secret generic tencentcloud-credentials \
--from-literal=TENCENTCLOUD_SECRET_ID="xxxx" \
--from-literal=TENCENTCLOUD_SECRET_KEY="xxxx" \
-n default
```


```shell
kubectl  apply -f deploy/inCluster/rbac.yaml
kubectl  apply -f deploy/inCluster/service.yaml
kubectl  apply -f deploy/inCluster/deployment.yaml
kubectl  apply -f deploy/inCluster/apiservice.yaml
```

### use kubectl plugin  shell version

```shell
cp kubectlplugins/kubectl-restart.sh  /usr/local/bin/kubectl-restart
file /usr/local/bin/kubectl-restart
/usr/local/bin/kubectl-restart: Bourne-Again shell script text executable, Unicode text, UTF-8 text
```



### use kubectl plugin  Golang version

```shell
go build  -o /usr/local/bin/kubectl-restart kubectlplugins/kubectl-restart.go
file /usr/local/bin/kubectl-restart
```


test
```shell
kubectl restart 10.205.13.24
```




### 
test priviliges  

```shell
bash e2e/get_kubeconfig.sh default
```

```shell
export  KUBECONFIG=./node-restarter-kubeconfig
```


```
kubectl get node
NAME           STATUS   ROLES    AGE    VERSION
10.205.13.24   Ready    <none>   4d3h   v1.30.0-tke.9

kubectl  delete node 10.205.13.24
Error from server (Forbidden): nodes "10.205.13.24" is forbidden: User "system:serviceaccount:default:node-restarter" cannot delete resource "nodes" in API group "" at the cluster scope

kubectl  restart  10.205.13.24
使用 Token 认证
请求失败，状态码: 500，响应: you can't reboot10.205.13.24because I run on it
```