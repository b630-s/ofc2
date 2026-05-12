#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
INSTALL_KAFKA_TEST_CLIENT="${INSTALL_KAFKA_TEST_CLIENT:-false}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[platform-kafka] %s\n' "$*"
}

preflight() {
  require_cmd kubectl

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not connected to a cluster. Run platform/scripts/02-connect-cluster.sh first." >&2
    exit 1
  fi

  if ! kubectl get deployment strimzi-cluster-operator -n platform-system >/dev/null 2>&1; then
    echo "Strimzi operator is not installed in platform-system. Run platform/scripts/03-0-deploy-platform.sh first." >&2
    exit 1
  fi
}

main() {
  preflight

  log "Deploying shared Kafka node pools and cluster into ${KAFKA_NAMESPACE}"
  kubectl apply -f "${REPO_ROOT}/platform/kafka/kafka-nodepool-controller.yaml"
  kubectl apply -f "${REPO_ROOT}/platform/kafka/kafka-nodepool-broker.yaml"
  kubectl apply -f "${REPO_ROOT}/platform/kafka/kafka-cluster.yaml"

  log "Waiting for Kafka cluster readiness"
  kubectl wait kafka/reference-kafka \
    --namespace "${KAFKA_NAMESPACE}" \
    --for=condition=Ready \
    --timeout=15m

  log "Creating shared Kafka topics"
  kubectl apply -f "${REPO_ROOT}/platform/kafka/kafka-topic-orders.yaml"
  kubectl apply -f "${REPO_ROOT}/platform/kafka/kafka-topic-orders-dlq.yaml"

  if [[ "${INSTALL_KAFKA_TEST_CLIENT}" == "true" ]]; then
    log "Deploying optional Kafka test client pod"
    kubectl apply -f "${REPO_ROOT}/platform/kafka/kafka-test-client.yaml"
  else
    log "Skipping Kafka test client pod; set INSTALL_KAFKA_TEST_CLIENT=true to install it"
  fi

  echo "Shared Kafka baseline deployed."
  echo "Bootstrap server: reference-kafka-kafka-bootstrap.${KAFKA_NAMESPACE}.svc.cluster.local:9092"
  echo "Topics: orders_raw, orders_dlq"
}

main "$@"
