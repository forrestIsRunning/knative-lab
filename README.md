# knative-lab

## 背景

Knative Serving 把「一个可以缩到零的 HTTP 服务」拆成多份 Kubernetes 对象。用户只提交 Service。Configuration 记住版本，Route 决定流量，Revision 下面才是 Deployment。入口再由 net-istio 写成 VirtualService。对象不放在一张图里，就看不出请求进了谁、空闲之后谁还在。

## 目标

在 kind 上安装 Knative Serving `knative-v1.23.0` 和它自带的 Istio，用一份 `echo-server` 把这些对象跑出来，并对照源码说明每一层谁写谁。

从这张图读起：[`docs/overview.md`](./docs/overview.md)。

```mermaid
---
config:
  flowchart:
    htmlLabels: true
    wrappingWidth: 220
    padding: 12
    useMaxWidth: false
    rankSpacing: 24
    nodeSpacing: 16
---
flowchart LR
  SVC["Service"] --> REV["Revision / Pod"]
  SVC --> ROUTE["Route"]
  ROUTE --> VS["VirtualService"]
  VS --> ACT["Activator"]
  ACT --> REV
```

这张图是本实验的实际走法：VirtualService 先到 Activator，再进 Revision 的 Pod。对象全名、以及没有请求之后谁还在，写在总图里。

阅读顺序和每一层的分叉在 [`docs/README.md`](./docs/README.md)。Activator 如何排队、Queue-Proxy 如何统计，写在 [这篇笔记](https://www.forrestisrunning.tech/article/knative)。

## 运行

```bash
cd ~/Projects/learning/knative-lab
make create
make verify
curl -H "Host: echo-server.default.example.com" http://127.0.0.1:18080
```

期望响应体是 `Hello World!`。集群名 `knative`，宿主机端口 `18080`。创建方式和不要踩的边界在 [`docs/cluster.md`](./docs/cluster.md)。

GitHub：https://github.com/forrestIsRunning/knative-lab
