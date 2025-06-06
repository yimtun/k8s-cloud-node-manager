# 部署在 k8s 集群内部

### 前提


###  加载清单文件

```shell
kubectl  apply -f ../deploy/inCluster/rbac.yaml
kubectl  apply -f ../deploy/inCluster/service.yaml
kubectl  apply -f ../deploy/inCluster/deployment.yaml
kubectl  apply -f ../deploy/apiservice.yaml
```



#### 从k8s 的 apiserver 验证


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

