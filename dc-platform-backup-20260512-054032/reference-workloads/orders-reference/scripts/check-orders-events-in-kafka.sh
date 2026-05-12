#!/usr/bin/env bash

set -euo pipefail

KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_TOPIC="${KAFKA_TOPIC:-orders_raw}"
KAFKA_CLIENT_POD="${KAFKA_CLIENT_POD:-kafka-test-client}"
KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-reference-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092}"
MAX_MESSAGES="${MAX_MESSAGES:-20}"

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

  kubectl exec -n "${KAFKA_NAMESPACE}" "${KAFKA_CLIENT_POD}" -- sh -c \
    "/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server '${KAFKA_BOOTSTRAP_SERVER}' --topic '${KAFKA_TOPIC}' --from-beginning --max-messages '${MAX_MESSAGES}'"
}

main "$@"
