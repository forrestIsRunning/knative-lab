# 文档阅读顺序

先看架构，再按需要看某一层怎么做决定。集群命令单独放，不写进对象说明。

## 先读

1. [`overview.md`](./overview.md) — 背景、目标、Knative 1.23 官方架构图，以及本机 `echo-server` 怎么对上这些图。
2. [`../README.md`](../README.md) — 这个仓库是什么。

## 某一层的分叉

| 顺序 | 文档 | 这层决定什么 |
|---|---|---|
| 配置和流量 | [`service-reconcile.md`](./service-reconcile.md) | 同名 Configuration / Route 何时创建，何时停下 |
| 副本 | [`revision-children.md`](./revision-children.md) | 为什么停在 Proxy，Activator 数为什么是 4 然后变成 3 |
| 入口 | [`kingress-to-virtualservice.md`](./kingress-to-virtualservice.md) | 为什么是两份 VirtualService，而且不另造 Gateway |

## 操作

[`cluster.md`](./cluster.md) — `make create`、端口、kubeconfig。

数据面长文在 [Knative：Service、Revision 与 Scale-to-Zero](https://www.forrestisrunning.tech/article/knative)。源码不在本仓库，clone 在 `~/Projects/learning/knative-serving` 和 `~/Projects/learning/knative-net-istio`。
