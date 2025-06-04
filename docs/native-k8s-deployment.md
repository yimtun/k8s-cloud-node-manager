# 部署在 k8s 集群内部

## 生成证书


如果部署的namespace 不是default需要对应修改文件hack/gen.sh  将default 为目标namespace名称

```shell
cd ../hack
sh gen.sh
```

会生成一个文件 用于 apiservice 的 caBundle 填值
certs/caBundle.txt


### 修改配置文件

修改文件 deploy/inCluster/apiservice.yaml  设置 caBundle


### 创建secret 存储证书 该证书用于 apiserver 运行的时候加载

```shell
kubectl delete secret extended-api-tls -n default
cd  ../certs/
kubectl create secret tls extended-api-tls --cert=tls.crt --key=tls.key -n default
```


### 创建 secret 用于 操作云接口的凭证

也可以使用   deploy/inCluster/secret.yaml 创建
当前使用命令行创建

```shell
kubectl delete secret tencentcloud-credentials -n default
kubectl create secret generic tencentcloud-credentials \
  --from-literal=TENCENTCLOUD_SECRET_ID="xxxx" \
  --from-literal=TENCENTCLOUD_SECRET_KEY="xxxx" \
  -n default
```



###  加载清单文件

```shell
kubectl  apply -f ../deploy/inCluster/rbac.yaml
kubectl  apply -f ../deploy/inCluster/service.yaml
kubectl  apply -f ../deploy/inCluster/deployment.yaml
kubectl  apply -f ../deploy/inCluster/apiservice.yaml
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



从注册到 k8s service 的 入口测试. 10.211.55.2 是service 的地址

#### 从k8s 的 接口验证







从 k8s 接口地址  10.211.55.18:6443

先从 kubeconfig中获取证书

```bash
cd  ../hack
sh  get_certs_from_kubeconfig.sh
```



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

