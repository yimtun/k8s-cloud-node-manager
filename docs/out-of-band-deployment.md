# 部署在 k8s 集群外部


**用于调试开发环境使用**

## 生成证书

修改下证书脚本

```bash
vim hack/gen.sh
IP:10.211.55.2   #将2处 10.211.55.2 替换为 在集群外运行时 服务运行时机ip 即可
```



```shell
cd hack
sh gen.sh
```

会生成一个文件 用于 apiservice 的 caBundle 填值
certs/caBundle.txt



### 修改配置文件

请确保已经设置好了  文件deploy/apiservice.yaml的caBundle



deploy/outCluster/service.yaml

需要设置一个ExternalName Service 将你本地运行的myapiserver 暴露给 Kubernetes apiserver 不一定是myapiser的实际运行ip和端口 也可以是经过代理后的入口 只要证书和入口的域名匹配和网络可达即可

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


```bash
kubectl apply -f deploy/apiservice.yaml
kubectl apply -f deploy/outCluster/service.yaml
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

运行前 加载 云接口认证信息   启动apiserver 

```bash
export TENCENTCLOUD_SECRET_ID="xxx"
export TENCENTCLOUD_SECRET_KEY="xxx"
export TENCENTCLOUD_REGION="xxx"

export  AWS_ACCESS_KEY_ID="xxxx"
export  AWS_SECRET_ACCESS_KEY="xxxx" 
export  AWS_REGION="xxxx"
```





### for mock  


当前的测试集群 不是托管的k8s 集群 所以需要冒充下 dev 节点是 腾讯云的服务器


```shell
kubectl patch node dev -p '{"spec":{"providerID":"qcloud:///800006/ins-lxaytb49"}}'
```

```shell
kubectl get node dev -o json | jq '.spec.providerID'
```




如果不值当 kubeconfig 会使用当前用户加目录下的  .kube/config 文件

```shell
cd ..
go run apiserver.go  --kubeconfig extended-api-server-kubeconfig
```




```shell
kubectl get --raw   "/apis/infraops.michael.io/v1" | jq .
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
--cacert ../certs/ca.crt   \
--cert ../certs/tls.crt   \
--key  ../certs/tls.key  \
 "https://127.0.0.1:/apis/infraops.michael.io/v1/nodes/xxnode/restart"
```

从注册到 k8s service 的 入口测试. 10.211.55.2 是service 的地址


```bash
curl -X POST   \
--cacert ../certs/ca.crt   \
--cert ../certs/tls.crt   \
--key  ../certs/tls.key  \
 "https://10.211.55.2:/apis/infraops.michael.io/v1/nodes/xxnode/restart"
```


#### 从k8s 的 接口验证



```bash
cd  ../hack
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
go build  -o /usr/local/bin/kubectl-restart ../kubectlplugins/kubectl-restart.go
```


```shell
kubectl get  node
```

```shell
kubectl restart dev
```
