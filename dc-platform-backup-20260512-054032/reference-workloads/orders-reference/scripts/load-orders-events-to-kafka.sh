#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_TOPIC="${KAFKA_TOPIC:-orders_raw}"
KAFKA_CLIENT_POD="${KAFKA_CLIENT_POD:-kafka-test-client}"
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-reference-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092}"
EVENTS_FILE="${EVENTS_FILE:-${REPO_ROOT}/reference-workloads/data/sample-events.json}"
REMOTE_EVENTS_FILE="/tmp/orders-events.json"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[orders-kafka-load] %s\n' "$*"
}

preflight() {
  require_cmd kubectl

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not connected to a cluster. Run platform/scripts/02-connect-cluster.sh first." >&2
    exit 1
  fi

  if [[ ! -f "${EVENTS_FILE}" ]]; then
    echo "events file not found: ${EVENTS_FILE}" >&2
    exit 1
  fi

  if ! kubectl get pod "${KAFKA_CLIENT_POD}" -n "${KAFKA_NAMESPACE}" >/dev/null 2>&1; then
    cat >&2 <<EOF
Kafka client pod ${KAFKA_CLIENT_POD} was not found in namespace ${KAFKA_NAMESPACE}.

Install it with:
  INSTALL_KAFKA_TEST_CLIENT=true ./platform/scripts/03-1-deploy-kafka.sh
EOF
    exit 1
  fi
}

main() {
  preflight

  log "Copying sample events into ${KAFKA_CLIENT_POD}"
  kubectl exec -i -n "${KAFKA_NAMESPACE}" "${KAFKA_CLIENT_POD}" -- sh -c "cat > '${REMOTE_EVENTS_FILE}'" < "${EVENTS_FILE}"

  log "Producing events from ${EVENTS_FILE} into topic ${KAFKA_TOPIC}"
  kubectl exec -n "${KAFKA_NAMESPACE}" "${KAFKA_CLIENT_POD}" -- sh -c \
    "cat '${REMOTE_EVENTS_FILE}' | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server '${KAFKA_BOOTSTRAP_SERVER}' --topic '${KAFKA_TOPIC}' >/dev/null"

  event_count="$(wc -l < "${EVENTS_FILE}" | tr -d '[:space:]')"

  echo "Loaded ${event_count} events into Kafka topic ${KAFKA_TOPIC}."
  echo "Bootstrap server: ${KAFKA_BOOTSTRAP_SERVER}"
  echo "Client pod: ${KAFKA_CLIENT_POD}"
}

main "$@"
