#!/usr/bin/env bash
# Pull an image on the host, then import it into kind nodes.
# kind load docker-image fails on Docker Desktop multi-arch indexes;
# docker save | ctr import works.
# kind nodes cannot dial the host's 127.0.0.1:1087 proxy. Importing from the
# host avoids that path. cluster/up.sh still rewrites the node proxy so the
# Istio and Knative install can pull its own images.
set -euo pipefail

CLUSTER="${KIND_CLUSTER_NAME:-knative}"
if [[ $# -lt 1 ]]; then
  echo "usage: $0 <image> [image...]" >&2
  exit 2
fi

if ! docker info >/dev/null 2>&1 && [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
  PATH="/Applications/Docker.app/Contents/Resources/bin:${PATH}"
fi

nodes="$(env -u KUBECONFIG kind get nodes --name "${CLUSTER}")"
if [[ -z "${nodes}" ]]; then
  echo "no nodes for kind cluster ${CLUSTER}" >&2
  exit 1
fi

for image in "$@"; do
  docker pull "${image}"
  while IFS= read -r node; do
    echo "import ${image} -> ${node}"
    docker save "${image}" | docker exec -i "${node}" ctr -n k8s.io images import --snapshotter=overlayfs -
  done <<< "${nodes}"
done
