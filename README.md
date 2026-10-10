# knative-lab

kind 上的 Knative Serving 与 Istio 实验。笔记只追控制面：哪个控制器 watch 哪个对象，reconcile 写回什么。

覆盖两段：

- **Knative Serving** `knative-v1.23.0`（Service、Configuration、Revision、KPA、SKS）
- **net-istio** 同一 tag 自带的 Istio 1.29.2（Ingress 到 VirtualService）

GitHub：https://github.com/forrestIsRunning/knative-lab 。本地目录：`~/Projects/learning/knative-lab`。

对照表和阅读顺序：[`docs/overview.md`](./docs/overview.md)、[`docs/README.md`](./docs/README.md)。数据面，包括 Activator、Queue-Proxy 和缩到零之后的请求路径，写在 [Knative：Service、Revision 与 Scale-to-Zero](https://www.forrestisrunning.tech/article/knative)。

kind 集群名是 `knative`，context 是 `kind-knative`。只有 1 个 control-plane，没有 worker。

## 入口

| 入口 | 花什么 | 命令 |
|---|---|---|
| kind 集群和 Serving | Docker / kind，约 6 GB 可用内存 | `make create`、`make verify` |
| 只读对象 | 已经装好的集群 | `make status`，或笔记末尾的 `kubectl --kubeconfig .kube/config` |

## kind 集群

`make create` 会把 context `kind-knative` 加进 `kubectx`，但保持当前 context 不变。同名集群已经存在时，命令留下它，不删除重建，然后继续安装清单。

### 前置条件

- Docker Desktop 正在运行（`docker info` 成功）
- `kind`、`kubectl`
- Docker 剩余内存至少 4 GB。官方单节点安装要求大约 6 GB。不够时 `make create` 直接退出

```bash
docker info >/dev/null
kind version
kubectl version --client
```

Docker 命令不在 `PATH` 里，或 `/usr/local/bin/docker` 指向坏掉的 OrbStack 符号链接时，`Makefile` 改用 Docker Desktop 自带的二进制。

### 使用

```bash
cd ~/Projects/learning/knative-lab

make create
make nodes
make status
make verify
make context-check
make delete
```

`make create` 把 kubeconfig 写到仓库里的 `.kube/config`，再 `make register`：把 `kind-knative` 写入 `~/.kube/config`，然后把 current-context 切回原来的集群。

```bash
kubectx                  # 列表里应有 kind-knative
kubectx kind-knative     # 切到这个实验
kubectl get nodes
kubectx -                # 切回上一个 context
```

不切 context 也可以读集群：

```bash
kubectl --kubeconfig .kube/config get nodes
```

不要直接跑 `kind export kubeconfig --name knative`。这条会把 current-context 切到 `kind-knative`。用 `make register`。

`make delete` 只删除名为 `knative` 的 kind 集群，并从 `~/.kube/config` 去掉 context `kind-knative`。

集群配置见 [`cluster/kind.yaml`](./cluster/kind.yaml)。control-plane 映射本机 `18080 -> 31080`、`18443 -> 31443`。`8080` 和 `8443` 属于 kind 集群 `k8s-lab`，不要改到这两个端口上。

版本和发布物 URL 钉在 [`versions.env`](./versions.env)。kind 节点镜像是 kind v0.32.0 的默认镜像 Kubernetes 1.36.1。Knative 1.23 要求 Kubernetes 不低于 1.34。

源码不进这个仓库。对照笔记时使用这两个检出：

- `~/Projects/learning/knative-serving`，tag `knative-v1.23.0`，commit `7ed4aa2ab601`
- `~/Projects/learning/knative-net-istio`，tag `knative-v1.23.0`，commit `25e9acac1720`

### 安装顺序里不要多跑的步骤

不要跑 `istioctl` 去装另一份最新 Istio。Istio 用 net-istio 发布物里的 `istio.yaml`。

不要对这份 `istio.yaml` 再执行 `kubectl apply -l knative.dev/crd-install=true`。`knative-v1.23.0` 的清单没有这个标签，kubectl 1.36 会因没有对象而失败。`cluster/up.sh` 直接 apply 整份文件。

不要安装 Eventing，也不要打开全命名空间的 sidecar 注入。

kind 没有云负载均衡。脚本把 `istio-ingressgateway` 改成 NodePort，只给名为 `http2` 和 `https` 的端口填 `31080` 和 `31443`，保留 status-port。`config-network` 的 ingress class 设为 `istio.ingress.networking.knative.dev`。`config-domain` 补上 `example.com`。

### 示例 Service

```bash
make verify
curl -H "Host: echo-server.default.example.com" http://127.0.0.1:18080
```

清单是 [`manifests/echo-server.yaml`](./manifests/echo-server.yaml)，镜像 `ghcr.io/knative/helloworld-go:latest`。验证通过时期望响应体是 `Hello World!`。

### 镜像

kind 节点访问不了本机 `127.0.0.1:1087` 代理。节点里的这个地址不是宿主机。`make create` 在创建集群时把回环代理改成 `host.docker.internal`。已经建好的节点如果还指着回环地址，脚本给 containerd 写同样的代理；代理文件已经是改写后的值时，不再重启 containerd。

额外镜像在宿主机拉取再导入，不要用 `kind load docker-image`（Docker Desktop 的多架构 index 上会失败）：

```bash
make load-image IMG=ghcr.io/knative/helloworld-go:latest
```
