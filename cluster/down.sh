#!/usr/bin/env bash
# Delete only the kind cluster named in versions.env.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
ensure_docker

# Always pass the lab kubeconfig so kind delete does not edit ~/.kube/config.
# unregister_system_context removes only context kind-knative afterwards.
if env -u KUBECONFIG kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  mkdir -p "${ROOT}/.kube"
  if [[ ! -f "${LAB_KUBECONFIG}" ]]; then
    env -u KUBECONFIG kind get kubeconfig --name "${CLUSTER_NAME}" > "${LAB_KUBECONFIG}"
  fi
  env -u KUBECONFIG kind delete cluster --name "${CLUSTER_NAME}" --kubeconfig "${LAB_KUBECONFIG}"
else
  echo "kind cluster ${CLUSTER_NAME} is not present"
fi
rm -f "${LAB_KUBECONFIG}"
unregister_system_context
