# 文档阅读顺序

本仓库记录 kind 集群 `knative` 上的 Knative Serving 和 net-istio。笔记按控制器分段。数据面，包括 Activator 排队、Queue-Proxy 和请求进 Pod 的路径，写在博客里，不要和这里的控制面笔记当成同一篇。

## 先读

1. [`overview.md`](./overview.md) — Service、Revision、net-istio 三段各写什么，以及哪些事实不能混。
2. 根目录 [`../README.md`](../README.md) — `make create` / `make verify` 和端口。

## 按控制器

| 控制器 | 文档 | 本机能跑到哪 |
|---|---|---|
| Service、Configuration | [`service-reconcile.md`](./service-reconcile.md) | `ksvc/echo-server` Ready，Revision `echo-server-00001` |
| Revision、KPA、SKS | [`revision-children.md`](./revision-children.md) | 有流量时 Activator 数 4；缩到零后副本 0，Activator 数 3，Revision 仍 Ready |
| Route、net-istio | [`kingress-to-virtualservice.md`](./kingress-to-virtualservice.md) | 两份 VirtualService；没有 per-ingress Gateway，也没有 per-revision VirtualService |

示例清单是 [`../manifests/echo-server.yaml`](../manifests/echo-server.yaml)。`make verify` 提交它。

## 不在本仓库

- 数据面长文在 [Knative：Service、Revision 与 Scale-to-Zero](https://www.forrestisrunning.tech/article/knative)。这里不重写 Activator、Queue-Proxy、指标、WASM 和 session affinity。
- 上游源码 clone 在 `~/Projects/learning/knative-serving` 和 `~/Projects/learning/knative-net-istio`，tag 都是 `knative-v1.23.0`。本仓库不收录源码。
- 不安装 Eventing、Kafka、RabbitMQ、cert-manager、HPA、Functions。
- 不打开全命名空间的 sidecar 注入。
- kind 集群 `k8s-lab`（context `kind-k8s-lab`，宿主机端口 `8080` / `8443`）是另一个仓库的集群。本仓库不创建、不删除它。
