# 怎么把这套对象跑在 kind 上

架构在 [overview.md](./overview.md)。这里只留创建集群和查看对象要用的事实。

集群名 `knative`，context `kind-knative`，一个 control-plane。宿主机 `18080` / `18443` 对应节点端口 `31080` / `31443`。`8080` / `8443` 属于另一个集群 `k8s-lab`。

```bash
cd ~/Projects/learning/knative-lab
make create
make verify
make status
curl -H "Host: echo-server.default.example.com" http://127.0.0.1:18080
```

`make create` 发现同名集群就留下，不删除重建。kubeconfig 写在仓库 `.kube/config`。`make register` 把 context 放进 `~/.kube/config` 之后，把 current-context 切回原来的值。不要直接跑 `kind export kubeconfig --name knative`，那条会把 current-context 改掉。

```bash
kubectl --kubeconfig .kube/config get nodes
```

域名是 `example.com`，ingress class 是 `istio.ingress.networking.knative.dev`。Istio 用 net-istio `knative-v1.23.0` 发布物里的 `istio.yaml`，不要再装一份最新 Istio。这份清单没有 `knative.dev/crd-install` 标签，安装脚本只 apply 一次。不安装 Eventing，也不打开全命名空间的 sidecar 注入。

官方单节点安装大约要 6 GB 内存。剩余不足 4 GB 时 `make create` 退出。节点访问不了宿主机上的 `127.0.0.1:1087`。创建时若代理指向回环地址，脚本改写成 `host.docker.internal`。另外的镜像用 `make load-image IMG=<ref>`，在宿主机拉取再导入节点。

`make delete` 只删除名为 `knative` 的集群。版本钉在 `versions.env`。
