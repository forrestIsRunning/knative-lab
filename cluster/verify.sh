#!/usr/bin/env bash
# Apply the echo Service and check the objects the controllers should write.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_context

kube apply -f "${ROOT}/samples/echo-server.yaml"

echo "wait for ksvc/${SAMPLE_NAME}"
if ! kube wait --for=condition=Ready "ksvc/${SAMPLE_NAME}" -n "${SAMPLE_NAMESPACE}" --timeout=300s; then
  kube get ksvc,configuration,revision,route -n "${SAMPLE_NAMESPACE}" >&2 || true
  kube describe "ksvc/${SAMPLE_NAME}" -n "${SAMPLE_NAMESPACE}" >&2 || true
  exit 1
fi

host="${SAMPLE_NAME}.${SAMPLE_NAMESPACE}.${DOMAIN}"
url="http://127.0.0.1:${HOST_HTTP_PORT}"
echo "curl -H Host:${host} ${url}"
body="$(curl -fsS --max-time 30 -H "Host: ${host}" "${url}")"
printf '%s\n' "${body}"

rev="$(kube get "ksvc/${SAMPLE_NAME}" -n "${SAMPLE_NAMESPACE}" -o jsonpath='{.status.latestCreatedRevisionName}')"
if [[ -z "${rev}" ]]; then
  echo "ksvc ${SAMPLE_NAME} has no latestCreatedRevisionName" >&2
  exit 1
fi

echo "revision ${rev}"
kube get "configuration/${SAMPLE_NAME}" "route/${SAMPLE_NAME}" "revision/${rev}" -n "${SAMPLE_NAMESPACE}"
kube get "deploy/${rev}-deployment" -n "${SAMPLE_NAMESPACE}"
kube get "podautoscaler/${rev}" -n "${SAMPLE_NAMESPACE}"
kube get "serverlessservice/${rev}" -n "${SAMPLE_NAMESPACE}"
kube get "svc/${rev}" "svc/${rev}-private" -n "${SAMPLE_NAMESPACE}"
kube get "ingress.networking.internal.knative.dev/${SAMPLE_NAME}" -n "${SAMPLE_NAMESPACE}"
kube get "virtualservice/${SAMPLE_NAME}-ingress" "virtualservice/${SAMPLE_NAME}-mesh" -n "${SAMPLE_NAMESPACE}"

echo "verify ok"
