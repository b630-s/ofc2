#!/usr/bin/env bash

set -euo pipefail

YES="false"

confirm() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N]: " answer
  [[ "${answer}" =~ ^[Yy]$ ]]
}

cleanup_release() {
  local namespace="$1"
  local release="$2"
  if helm status "${release}" --namespace "${namespace}" >/dev/null 2>&1; then
    echo "Uninstalling ${release} from ${namespace}..."
    helm uninstall "${release}" --namespace "${namespace}" --wait --timeout 10m
  fi
}

delete_if_present() {
  local type="$1"
  local name="$2"
  local namespace="$3"
  if kubectl get "${type}" "${name}" --namespace "${namespace}" >/dev/null 2>&1; then
    kubectl delete "${type}" "${name}" --namespace "${namespace}" --ignore-not-found
  fi
}

delete_matching_pvcs() {
  local namespace="$1"
  local prefix="$2"
  local pvcs

  pvcs="$(kubectl get pvc --namespace "${namespace}" --no-headers 2>/dev/null | awk -v wanted="${prefix}" '$1 ~ "^" wanted { print $1 }')"
  if [[ -z "${pvcs}" ]]; then
    return
  fi

  while IFS= read -r pvc; do
    [[ -z "${pvc}" ]] && continue
    kubectl delete pvc "${pvc}" --namespace "${namespace}" --ignore-not-found
  done <<< "${pvcs}"
}

delete_kafka_workloads() {
  if ! kubectl get namespace kafka >/dev/null 2>&1; then
    return
  fi

  echo "Deleting Strimzi-managed Kafka resources from kafka namespace..."
  kubectl delete kafkatopic --all -n kafka --ignore-not-found --wait=false || true
  kubectl delete kafka --all -n kafka --ignore-not-found --wait=false || true
  kubectl delete kafkanodepool --all -n kafka --ignore-not-found --wait=false || true

  local topics
  topics="$(kubectl get kafkatopic -n kafka -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${topics}" ]]; then
    for topic in ${topics}; do
      kubectl patch kafkatopic "${topic}" -n kafka --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    done
  fi
}

main() {
  if ! command -v kubectl >/dev/null 2>&1 || ! command -v helm >/dev/null 2>&1; then
    echo "kubectl and helm are required." >&2
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        YES="true"
        ;;
      --help|-h)
        echo "Usage: 06-cleanup-platform.sh [--yes]"
        exit 0
        ;;
      *)
        echo "unknown argument: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ "${YES}" != "true" ]]; then
    if ! confirm "Delete installed platform services and namespaces from the current cluster?"; then
      echo "Platform cleanup cancelled."
      exit 0
    fi
  fi

  echo "Cleaning up platform services only. AWS infrastructure is not touched."

  delete_kafka_workloads
  cleanup_release "polaris" "polaris"
  cleanup_release "monitoring" "kube-prometheus-stack"
  cleanup_release "ingress-nginx" "ingress-nginx"
  cleanup_release "airflow" "airflow"
  cleanup_release "platform-system" "spark-operator"
  cleanup_release "platform-system" "strimzi-kafka-operator"

  delete_if_present statefulset polaris-postgresql polaris
  delete_if_present service polaris-postgresql polaris
  delete_if_present service polaris-postgresql-headless polaris
  delete_if_present secret polaris-persistence polaris

  delete_matching_pvcs "polaris" "data-polaris-postgresql-"
  delete_matching_pvcs "airflow" "data-airflow-postgresql-"

  kubectl delete namespace airflow kafka monitoring polaris spark ingress-nginx platform-system --ignore-not-found

  echo "Platform cleanup completed."
  echo "If you also want to stop AWS charges, run infra/aws-proto/destroy-infra.sh."
}

main "$@"
