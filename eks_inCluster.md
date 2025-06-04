


```shell
kubectl --kubeconfig ./config-eks delete secret tencentcloud-credentials -n default
kubectl --kubeconfig ./config-eks create secret generic tencentcloud-credentials \
  --from-literal=TENCENTCLOUD_SECRET_ID="xxxx" \
  --from-literal=TENCENTCLOUD_SECRET_KEY="xxxx" \
  -n default
```





如果你不使用 eks 的 OIDC  需要创建  aws-credentials 

```shell
kubectl --kubeconfig ./config-eks delete secret aws-credentials -n default
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID="xxxx" \
  --from-literal=AWS_SECRET_ACCESS_KEY="xxxx" \
  -n default
```

you can find id and key by cli

```shell
cat  ~/.aws/credentials
```



```shell

kubectl --kubeconfig ./config-eks delete secret extended-api-tls -n default
kubectl --kubeconfig ./config-eks create secret tls extended-api-tls --cert=./certs/tls.crt --key=./certs/tls.key -n default
```




如果你不使用 eks 的 OIDC  需要执行 rbac.yaml

```shell
kubectl --kubeconfig ./config-eks apply -f deploy/inCluster/rbac.yaml 
```



如果你不使用 eks 的 OIDC  需要执行 deployment.yaml


```shell
kubectl --kubeconfig ./config-eks  apply -f deploy/inCluster/deployment.yaml  -n default
```


如果使用 eks 的 OIDC  需要执行 eks_oidc_deployment.yaml

```shell
kubectl --kubeconfig ./config-eks  apply -f deploy/inCluster/eks_oidc_deployment.yaml  -n default
```



```shell
kubectl --kubeconfig ./config-eks  apply -f deploy/inCluster/apiservice.yaml  -n default
```

```shell
kubectl --kubeconfig ./config-eks  apply -f deploy/inCluster/service.yaml  -n default
```



```shell
kubectl --kubeconfig ./config-eks   get apiservice v1.infraops.michael.io
```

```shell
kubectl get --raw   "/apis/infraops.michael.io/v1" | jq .
```

get token cli

```shell
aws eks get-token --cluster-name my-eks-cluster  --region us-east-1 | jq -r '.status.token'
```


kubeconfig use token tmep

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: 
    server: https://xxxxxx.us-east-1.eks.amazonaws.com
  name: arn:aws:eks:us-east-1:xxx:cluster/my-eks-cluster
contexts:
- context:
    cluster: arn:aws:eks:us-east-1:xxx:cluster/my-eks-cluster
    user: arn:aws:eks:us-east-1:xxx:cluster/my-eks-cluster
  name: arn:aws:eks:us-east-1:xxx:cluster/my-eks-cluster
current-context: arn:aws:eks:us-east-1:xxx:cluster/my-eks-cluster
kind: Config
preferences: {}
users:
- name: arn:aws:eks:us-east-1:xxx:cluster/my-eks-cluster
  user:
    token: tokenxxx
```

## test plugin


```shell
kubectl get node
```

```shell
kubectl restart ip-10-0-10-76.ec2.internal
```



