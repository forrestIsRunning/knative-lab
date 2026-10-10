# knative-lab

公开仓库：[forrestIsRunning/knative-lab](https://github.com/forrestIsRunning/knative-lab)

本地 kind 集群上的 Istio 与 Knative Serving 实验。笔记只追控制面：哪个控制器 watch 哪个对象，reconcile 写回什么。数据面，包括 Activator、Queue-Proxy 和缩到零之后的请求路径，写在 [Knative：Service、Revision 与 Scale-to-Zero](https://www.forrestisrunning.tech/article/knative)。

安装版本钉在 `versions.env`。当前是 Knative Serving `knative-v1.23.0`，Istio 来自同一版本 `net-istio` 发布物里的 `istio.yaml`，清单里的 ingress gateway 标的是 Istio 1.29.2。kind 节点镜像是 kind v0.32.0 的默认镜像 Kubernetes 1.36.1。Knative 1.23 要求 Kubernetes 不低于 1.34。

源码不进这个仓库。对照笔记时把两个 tag 克隆到同级目录：

- `knative-serving`，tag `knative-v1.23.0`，commit `7ed4aa2ab601`
- `knative-net-istio`，tag `knative-v1.23.0`，commit `25e9acac1720`

## 笔记

| 目录 | 内容 |
| --- | --- |
| [serving/service-reconcile.md](serving/service-reconcile.md) | Service 如何保证同名 Configuration 和 Route，Configuration 如何再写 Revision |
| [serving/revision-children.md](serving/revision-children.md) | Revision 如何写 Deployment 和 PodAutoscaler，KPA 如何写 ServerlessService，SKS 如何写 public / private Service |
| [net-istio/kingress-to-virtualservice.md](net-istio/kingress-to-virtualservice.md) | Route 写出的 Ingress 如何被 net-istio 收成 VirtualService |

## 集群

`cluster/up.sh` 创建名为 `knative` 的单节点 kind 集群，再按官方 YAML 顺序安装 Serving、Istio 和 net-istio。`knative-v1.23.0` 的 `istio.yaml` 没有 `knative.dev/crd-install` 标签，脚本直接 apply 整份清单。脚本把 `config-network` 的 ingress class 设为 `istio.ingress.networking.knative.dev`，把 `config-domain` 补上 `example.com`。kind 没有云负载均衡，脚本把 `istio-ingressgateway` 改成 NodePort，宿主机 `18080` 和 `18443` 映射到节点端口 `31080` 和 `31443`。`8080` 和 `8443` 留给本机另一个 kind 集群。

`cluster/down.sh` 只删除名为 `knative` 的 kind 集群。

官方单节点安装要求大约 6 GB 内存。`cluster/up.sh` 在 Docker 剩余内存不足 4 GB 时直接退出，避免把已经在跑的容器挤掉。Docker 命令不在 `PATH` 里时，脚本会改用 Docker Desktop 自带的二进制。宿主机代理如果指向 `127.0.0.1`，kind 会把这个地址抄进节点，节点里的 `127.0.0.1` 不是宿主机。脚本创建集群时把它改成 `host.docker.internal`。已经建好的节点如果还指着回环地址，脚本会给 containerd 写一份同样的代理再拉镜像。

```bash
./cluster/up.sh
./cluster/verify.sh
```

`cluster/verify.sh` 提交 `samples/echo-server.yaml`，等 `ksvc/echo-server` Ready，再用 Host 头访问：

```bash
curl -H "Host: echo-server.default.example.com" http://127.0.0.1:18080
```

这次不装 Eventing，也不打开全命名空间的 sidecar 注入。
