#!/usr/bin/env bash
# Create the kind cluster named in versions.env and install Knative Serving with Istio.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ensure_docker
grep -q "containerPort: ${NODE_HTTP_PORT}" "${ROOT}/cluster/kind.yaml"
grep -q "hostPort: ${HOST_HTTP_PORT}" "${ROOT}/cluster/kind.yaml"
grep -q "containerPort: ${NODE_HTTPS_PORT}" "${ROOT}/cluster/kind.yaml"
grep -q "hostPort: ${HOST_HTTPS_PORT}" "${ROOT}/cluster/kind.yaml"
check_docker_memory

# kind copies HTTP(S)_PROXY into the node. 127.0.0.1 inside the node is not the host.
rewrite_loopback_proxy() {
  local value="$1"
  value="${value//127.0.0.1/host.docker.internal}"
  value="${value//localhost/host.docker.internal}"
  printf '%s' "${value}"
}

fix_node_image_proxy() {
  local current rewritten
  current="$(docker exec "${CLUSTER_NAME}-control-plane" sh -c 'printf %s "${HTTPS_PROXY:-}"')"
  if [[ "${current}" != *127.0.0.1* && "${current}" != *localhost* ]]; then
    return 0
  fi
  rewritten="$(rewrite_loopback_proxy "${current}")"
  if docker exec "${CLUSTER_NAME}-control-plane" grep -qs "HTTPS_PROXY=${rewritten}" /etc/systemd/system/containerd.service.d/http-proxy.conf; then
    echo "containerd proxy already set to ${rewritten}"
    return 0
  fi
  echo "kind node proxy ${current} does not reach the host; containerd will use ${rewritten}"
  docker exec -i "${CLUSTER_NAME}-control-plane" sh -s -- "${rewritten}" <<'EOF'
set -eu
proxy="$1"
mkdir -p /etc/systemd/system/containerd.service.d
cat > /etc/systemd/system/containerd.service.d/http-proxy.conf <<UNIT
[Service]
Environment="HTTP_PROXY=${proxy}"
Environment="HTTPS_PROXY=${proxy}"
Environment="http_proxy=${proxy}"
Environment="https_proxy=${proxy}"
UNIT
systemctl daemon-reload
systemctl restart containerd
EOF
}

mkdir -p "${ROOT}/.kube"
if env -u KUBECONFIG kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster ${CLUSTER_NAME} already exists; leaving it in place"
else
  proxy_src="${http_proxy:-${HTTP_PROXY:-}}${https_proxy:-${HTTPS_PROXY:-}}"
  if [[ "${proxy_src}" == *127.0.0.1* || "${proxy_src}" == *localhost* ]]; then
    create_http="$(rewrite_loopback_proxy "${http_proxy:-${HTTP_PROXY:-}}")"
    create_https="$(rewrite_loopback_proxy "${https_proxy:-${HTTPS_PROXY:-}}")"
    echo "creating kind cluster with proxy ${create_https:-${create_http}}"
    HTTP_PROXY="${create_http}" HTTPS_PROXY="${create_https}" \
      http_proxy="${create_http}" https_proxy="${create_https}" \
      env -u KUBECONFIG kind create cluster \
        --name "${CLUSTER_NAME}" \
        --image "${KIND_NODE_IMAGE}" \
        --config "${ROOT}/cluster/kind.yaml" \
        --kubeconfig "${LAB_KUBECONFIG}"
  else
    env -u KUBECONFIG kind create cluster \
      --name "${CLUSTER_NAME}" \
      --image "${KIND_NODE_IMAGE}" \
      --config "${ROOT}/cluster/kind.yaml" \
      --kubeconfig "${LAB_KUBECONFIG}"
  fi
fi
# Refresh from kind's own store. This write stays inside the repo .kube/ and
# does not switch ~/.kube/config current-context. make register does that merge.
refresh_lab_kubeconfig
fix_node_image_proxy

apply_with_retry() {
  local url="$1"
  local attempt
  for attempt in 1 2 3 4 5 6; do
    if kube apply -f "${url}"; then
      return 0
    fi
    echo "apply failed for ${url}; retry ${attempt}" >&2
    sleep 10
  done
  return 1
}

echo "install serving CRDs"
apply_with_retry "${SERVING_CRDS_URL}"
echo "install serving core"
apply_with_retry "${SERVING_CORE_URL}"

# knative-v1.23.0 istio.yaml has no knative.dev/crd-install label.
# The documented selector apply matches nothing, and kubectl 1.36 exits 1.
# The file only contains built-in kinds, so one apply installs the CRDs and the control plane.
echo "install Istio ${ISTIO_VERSION}"
apply_with_retry "${ISTIO_URL}"
echo "install net-istio"
apply_with_retry "${NET_ISTIO_URL}"

kube patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch "{\"data\":{\"ingress-class\":\"${INGRESS_CLASS}\"}}"

kube patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch "{\"data\":{\"${DOMAIN}\":\"\"}}"

echo "publish istio-ingressgateway on nodePorts ${NODE_HTTP_PORT} and ${NODE_HTTPS_PORT}"
kube -n istio-system get svc istio-ingressgateway -o json | NODE_HTTP_PORT="${NODE_HTTP_PORT}" NODE_HTTPS_PORT="${NODE_HTTPS_PORT}" python3 -c '
import json, os, sys
svc = json.load(sys.stdin)
svc["spec"]["type"] = "NodePort"
wanted = {
    "http2": int(os.environ["NODE_HTTP_PORT"]),
    "https": int(os.environ["NODE_HTTPS_PORT"]),
}
seen = set()
for port in svc["spec"]["ports"]:
    name = port.get("name")
    if name in wanted:
        port["nodePort"] = wanted[name]
        seen.add(name)
missing = set(wanted) - seen
if missing:
    sys.exit("istio-ingressgateway is missing ports: " + ", ".join(sorted(missing)))
meta = {"name": svc["metadata"]["name"], "namespace": svc["metadata"]["namespace"]}
if "labels" in svc["metadata"]:
    meta["labels"] = svc["metadata"]["labels"]
if "annotations" in svc["metadata"]:
    meta["annotations"] = svc["metadata"]["annotations"]
json.dump({"apiVersion": "v1", "kind": "Service", "metadata": meta, "spec": svc["spec"]}, sys.stdout)
' | kube apply -f -

wait_namespace() {
  local ns="$1"
  local deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    if kube get pods -n "${ns}" --no-headers 2>/dev/null | grep -q .; then
      local bad
      bad="$(kube get pods -n "${ns}" --no-headers | awk '$3 != "Running" && $3 != "Completed" {print}')"
      if [[ -z "${bad}" ]]; then
        echo "${ns} pods are Running or Completed"
        return 0
      fi
    fi
    sleep 5
  done
  echo "timed out waiting for pods in ${ns}" >&2
  kube get pods -n "${ns}" >&2 || true
  return 1
}

wait_namespace istio-system
wait_namespace knative-serving

echo "gateway: curl -H \"Host: <service>.<namespace>.${DOMAIN}\" http://127.0.0.1:${HOST_HTTP_PORT}"
