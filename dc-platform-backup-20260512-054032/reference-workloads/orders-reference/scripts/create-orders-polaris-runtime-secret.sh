#!/usr/bin/env bash

set -euo pipefail

SPARK_NAMESPACE="${SPARK_NAMESPACE:-spark}"
POLARIS_SECRET_NAME="${POLARIS_SECRET_NAME:-reference-polaris-spark-credentials}"
POLARIS_USER_CLIENT_ID="${POLARIS_USER_CLIENT_ID:-}"
POLARIS_USER_CLIENT_SECRET="${POLARIS_USER_CLIENT_SECRET:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

preflight() {
  require_cmd kubectl

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not connected to a cluster. Run platform/scripts/02-connect-cluster.sh first." >&2
    exit 1
  fi

  if [[ -z "${POLARIS_USER_CLIENT_ID}" || -z "${POLARIS_USER_CLIENT_SECRET}" ]]; then
    echo "Set POLARIS_USER_CLIENT_ID and POLARIS_USER_CLIENT_SECRET before running this script." >&2
    exit 1
  fi
}

main() {
  preflight

  kubectl create secret generic "${POLARIS_SECRET_NAME}" \
    -n "${SPARK_NAMESPACE}" \
    --from-literal=client-id="${POLARIS_USER_CLIENT_ID}" \
    --from-literal=client-secret="${POLARIS_USER_CLIENT_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Created or updated secret ${POLARIS_SECRET_NAME} in namespace ${SPARK_NAMESPACE}."
}

main "$@"
