#!/usr/bin/env bash

set -euo pipefail

failure=0

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[validate] %s\n' "$*"
}

show_namespace_pods() {
  local namespace="$1"
  echo "Current pods in namespace ${namespace}:"
  kubectl get pods -n "${namespace}" -o wide || true
}

check_nodes() {
  log "Checking Kubernetes node readiness"
  kubectl get nodes
  if ! kubectl get nodes --no-headers | awk 'BEGIN { bad=0 } $2 != "Ready" { bad=1 } END { exit bad }'; then
    echo "Node readiness check failed." >&2
    failure=1
  fi
}

check_rollout() {
  local namespace="$1"
  local kind="$2"
  local name="$3"
  local label="$4"
  local timeout="${5:-300s}"

  log "Checking ${label} (${kind}/${name}) in namespace ${namespace}"

  if ! kubectl get "${kind}" "${name}" -n "${namespace}" >/dev/null 2>&1; then
    echo "${label} resource ${kind}/${name} not found in namespace ${namespace}." >&2
    show_namespace_pods "${namespace}"
    failure=1
    return
  fi

  if ! kubectl rollout status "${kind}/${name}" -n "${namespace}" --timeout="${timeout}"; then
    echo "${label} is not ready." >&2
    show_namespace_pods "${namespace}"
    failure=1
  fi
}

check_job_complete() {
  local namespace="$1"
  local name="$2"
  local label="$3"
  local timeout="${4:-300s}"

  log "Checking ${label} (job/${name}) in namespace ${namespace}"

  if ! kubectl get job "${name}" -n "${namespace}" >/dev/null 2>&1; then
    log "${label} job/${name} not found in namespace ${namespace}; treating this as acceptable if the dependent services are already healthy"
    return
  fi

  if ! kubectl wait --namespace "${namespace}" --for=condition=complete "job/${name}" --timeout="${timeout}" >/dev/null 2>&1; then
    echo "${label} did not complete." >&2
    show_namespace_pods "${namespace}"
    failure=1
  fi
}

check_monitoring() {
  check_rollout "monitoring" "deployment" "kube-prometheus-stack-operator" "Prometheus operator"
  check_rollout "monitoring" "deployment" "kube-prometheus-stack-grafana" "Grafana"
  check_rollout "monitoring" "deployment" "kube-prometheus-stack-kube-state-metrics" "kube-state-metrics"
  check_rollout "monitoring" "statefulset" "prometheus-kube-prometheus-stack-prometheus" "Prometheus server"
}

check_airflow() {
  check_rollout "airflow" "statefulset" "airflow-postgresql" "Airflow PostgreSQL"
  check_job_complete "airflow" "airflow-run-airflow-migrations" "Airflow database migration job"
  check_rollout "airflow" "deployment" "airflow-api-server" "Airflow API server"
  check_rollout "airflow" "deployment" "airflow-scheduler" "Airflow scheduler"
  check_rollout "airflow" "deployment" "airflow-dag-processor" "Airflow DAG processor"
  check_rollout "airflow" "deployment" "airflow-statsd" "Airflow statsd"
  if kubectl get statefulset airflow-triggerer -n airflow >/dev/null 2>&1; then
    check_rollout "airflow" "statefulset" "airflow-triggerer" "Airflow triggerer"
  elif kubectl get deployment airflow-triggerer -n airflow >/dev/null 2>&1; then
    check_rollout "airflow" "deployment" "airflow-triggerer" "Airflow triggerer"
  else
    echo "Airflow triggerer resource not found as either statefulset/airflow-triggerer or deployment/airflow-triggerer in namespace airflow." >&2
    show_namespace_pods "airflow"
    failure=1
  fi
}

check_polaris() {
  check_rollout "polaris" "statefulset" "polaris-postgresql" "Polaris PostgreSQL"
  check_rollout "polaris" "deployment" "polaris" "Polaris"
}

main() {
  require_cmd kubectl

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not connected to a cluster." >&2
    exit 1
  fi

  check_nodes
  check_rollout "platform-system" "deployment" "strimzi-cluster-operator" "Strimzi operator"
  check_rollout "platform-system" "deployment" "spark-operator-controller" "Spark operator controller"
  check_rollout "platform-system" "deployment" "spark-operator-webhook" "Spark operator webhook"
  check_monitoring
  check_airflow
  check_polaris

  if [[ "${failure}" -ne 0 ]]; then
    echo "Platform validation failed." >&2
    exit 1
  fi

  echo "Platform validation passed."
}

main "$@"
