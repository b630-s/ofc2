#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

preflight() {
  require_cmd kubectl
  require_cmd envsubst

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not connected to a cluster. Run platform/scripts/02-connect-cluster.sh first." >&2
    exit 1
  fi

  if [[ -z "${REFERENCE_SPARK_IMAGE:-}" ]]; then
    echo "Set REFERENCE_SPARK_IMAGE before running this script." >&2
    exit 1
  fi
}

main() {
  preflight
  envsubst < "${REPO_ROOT}/reference-workloads/orders-reference/spark/manifests/spark-app-kafka-to-raw.yaml" | kubectl apply -f -
}

main "$@"
