#!/usr/bin/env bash
# Shared helpers for cluster/up.sh, cluster/down.sh, and cluster/verify.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
# shellcheck disable=SC1091
source "${ROOT}/versions.env"
set +a

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi
  local app="/Applications/Docker.app/Contents/Resources/bin"
  if [[ -x "${app}/docker" ]]; then
    export PATH="${app}:${PATH}"
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "docker is not available" >&2
    exit 1
  fi
}

kube() {
  kubectl --context "${KUBE_CONTEXT}" "$@"
}

require_context() {
  if ! kubectl config get-contexts -o name | grep -qx "${KUBE_CONTEXT}"; then
    echo "kubectl context ${KUBE_CONTEXT} is missing. Run cluster/up.sh first." >&2
    exit 1
  fi
}

# Refuse to start another cluster when Docker has little free memory.
# Knative's single-node install asks for 6 GB. This guard uses 4 GB free
# as the minimum so existing containers are not pushed into OOM.
check_docker_memory() {
  python3 - <<'PY'
import os, subprocess, sys

def to_bytes(text):
    text = text.strip()
    units = {"B": 1, "KiB": 2**10, "MiB": 2**20, "GiB": 2**30, "TiB": 2**40,
             "KB": 10**3, "MB": 10**6, "GB": 10**9, "TB": 10**12}
    for unit, scale in sorted(units.items(), key=lambda item: -len(item[0])):
        if text.endswith(unit):
            return int(float(text[: -len(unit)]) * scale)
    return int(float(text))

total = int(subprocess.check_output(["docker", "info", "--format", "{{.MemTotal}}"], text=True).strip())
stats = subprocess.check_output(
    ["docker", "stats", "--no-stream", "--format", "{{.Name}}\t{{.MemUsage}}"],
    text=True,
)
used = 0
rows = []
for line in stats.splitlines():
    if not line.strip():
        continue
    name, mem = line.split("\t", 1)
    current = mem.split("/", 1)[0].strip()
    used += to_bytes(current)
    rows.append((name, current))
free = total - used
need = 4 * 2**30
print(f"docker memory: total={total/2**30:.2f} GiB used={used/2**30:.2f} GiB free={free/2**30:.2f} GiB")
if free < need:
    print("not enough free Docker memory for Istio and Knative Serving.", file=sys.stderr)
    print("free at least 4 GiB, then rerun cluster/up.sh. Current containers:", file=sys.stderr)
    for name, current in rows:
        print(f"  {name}\t{current}", file=sys.stderr)
    sys.exit(1)
PY
}
