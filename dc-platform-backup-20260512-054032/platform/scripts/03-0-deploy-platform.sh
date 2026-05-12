#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${TF_DIR:-${REPO_ROOT}/infra/aws-proto}"

PLATFORM_NAMESPACE="${PLATFORM_NAMESPACE:-platform-system}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
AIRFLOW_CHART_VERSION="${AIRFLOW_CHART_VERSION:-1.20.0}"
SPARK_OPERATOR_CHART_VERSION="${SPARK_OPERATOR_CHART_VERSION:-2.4.0}"
STRIMZI_CHART_VERSION="${STRIMZI_CHART_VERSION:-0.51.0}"
INGRESS_NGINX_CHART_VERSION="${INGRESS_NGINX_CHART_VERSION:-4.14.1}"
KUBE_PROMETHEUS_STACK_CHART_VERSION="${KUBE_PROMETHEUS_STACK_CHART_VERSION:-80.13.3}"
POLARIS_CHART_VERSION="${POLARIS_CHART_VERSION:-1.3.0-incubating}"

ENABLE_AIRFLOW="${ENABLE_AIRFLOW:-true}"
ENABLE_SPARK="${ENABLE_SPARK:-true}"
ENABLE_STRIMZI="${ENABLE_STRIMZI:-true}"
ENABLE_INGRESS="${ENABLE_INGRESS:-false}"
ENABLE_MONITORING="${ENABLE_MONITORING:-true}"
ENABLE_POLARIS="${ENABLE_POLARIS:-true}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[platform] %s\n' "$*"
}

resolve_tf_output() {
  local output_name="$1"

  if ! command -v terraform >/dev/null 2>&1; then
    return 1
  fi

  if [[ ! -d "${TF_DIR}" ]]; then
    return 1
  fi

  terraform -chdir="${TF_DIR}" output -raw "${output_name}" 2>/dev/null
}

ensure_role_arn() {
  local enabled="$1"
  local env_var_name="$2"
  local output_name="$3"
  local component_label="$4"
  local current_value="${!env_var_name:-}"

  if [[ "${enabled}" != "true" ]]; then
    return
  fi

  if [[ -n "${current_value}" ]]; then
    log "Using ${component_label} IAM role ARN from ${env_var_name}"
    return
  fi

  current_value="$(resolve_tf_output "${output_name}" || true)"
  if [[ -n "${current_value}" ]]; then
    export "${env_var_name}=${current_value}"
    log "Resolved ${component_label} IAM role ARN from Terraform output ${output_name}"
    return
  fi

  echo "${env_var_name} is required when ${component_label} is enabled. Export it explicitly or run this script from a repo with Terraform state in ${TF_DIR}." >&2
  exit 1
}

preflight() {
  require_cmd kubectl
  require_cmd helm

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not connected to a cluster. Run platform/scripts/02-connect-cluster.sh first." >&2
    exit 1
  fi

  ensure_role_arn "${ENABLE_SPARK}" "SPARK_S3_ROLE_ARN" "spark_s3_role_arn" "Spark"
  ensure_role_arn "${ENABLE_AIRFLOW}" "AIRFLOW_S3_ROLE_ARN" "airflow_s3_role_arn" "Airflow"
  ensure_role_arn "${ENABLE_POLARIS}" "POLARIS_S3_ROLE_ARN" "polaris_s3_role_arn" "Polaris"

  if [[ "${ENABLE_POLARIS}" == "true" ]]; then
    if [[ -z "${POLARIS_DB_PASSWORD:-}" ]]; then
      echo "POLARIS_DB_PASSWORD is required when ENABLE_POLARIS=true." >&2
      exit 1
    fi
  fi
}

add_helm_repos() {
  if [[ "${ENABLE_AIRFLOW}" == "true" ]]; then
    helm repo add apache-airflow https://airflow.apache.org --force-update
  fi

  if [[ "${ENABLE_SPARK}" == "true" ]]; then
    helm repo add spark-operator https://kubeflow.github.io/spark-operator --force-update
  fi

  if [[ "${ENABLE_STRIMZI}" == "true" ]]; then
    helm repo add strimzi https://strimzi.io/charts/ --force-update
  fi

  if [[ "${ENABLE_POLARIS}" == "true" ]]; then
    helm repo add polaris https://downloads.apache.org/incubator/polaris/helm-chart --force-update
  fi

  if [[ "${ENABLE_INGRESS}" == "true" ]]; then
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
  fi

  if [[ "${ENABLE_MONITORING}" == "true" ]]; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
  fi

  helm repo update
}

install_foundations() {
  log "Applying platform namespaces and shared service accounts"
  kubectl apply -f "${REPO_ROOT}/platform/namespaces.yaml"
  kubectl apply -f "${REPO_ROOT}/platform/service-accounts.yaml"

  annotate_service_account_role spark spark-sa SPARK_S3_ROLE_ARN
  annotate_service_account_role airflow airflow-sa AIRFLOW_S3_ROLE_ARN
  annotate_service_account_role polaris polaris-sa POLARIS_S3_ROLE_ARN
}

annotate_service_account_role() {
  local namespace="$1"
  local service_account="$2"
  local role_env_var="$3"
  local role_arn="${!role_env_var:-}"

  if [[ -z "${role_arn}" ]]; then
    return
  fi

  log "Annotating ${namespace}/${service_account} with IAM role ${role_arn}"
  kubectl annotate serviceaccount "${service_account}" \
    --namespace "${namespace}" \
    eks.amazonaws.com/role-arn="${role_arn}" \
    --overwrite
}

install_strimzi() {
  if [[ "${ENABLE_STRIMZI}" != "true" ]]; then
    echo "Skipping Strimzi. Set ENABLE_STRIMZI=true to install it."
    return
  fi

  log "Installing Strimzi operator into ${PLATFORM_NAMESPACE}"
  helm upgrade --install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
    --namespace "${PLATFORM_NAMESPACE}" \
    --create-namespace \
    --version "${STRIMZI_CHART_VERSION}" \
    --values "${REPO_ROOT}/platform/values-strimzi-operator.yaml" \
    --wait \
    --timeout 10m
}

install_spark_operator() {
  if [[ "${ENABLE_SPARK}" != "true" ]]; then
    echo "Skipping Spark Operator. Set ENABLE_SPARK=true to install it."
    return
  fi

  log "Installing Spark Operator into ${PLATFORM_NAMESPACE}"
  helm upgrade --install spark-operator spark-operator/spark-operator \
    --namespace "${PLATFORM_NAMESPACE}" \
    --create-namespace \
    --version "${SPARK_OPERATOR_CHART_VERSION}" \
    --values "${REPO_ROOT}/platform/values-spark-operator.yaml" \
    --wait \
    --timeout 10m
}

install_airflow() {
  if [[ "${ENABLE_AIRFLOW}" != "true" ]]; then
    echo "Skipping Airflow. Set ENABLE_AIRFLOW=true to install it."
    return
  fi

  log "Installing Airflow into airflow namespace"
  helm upgrade --install airflow apache-airflow/airflow \
    --namespace airflow \
    --create-namespace \
    --reset-values \
    --version "${AIRFLOW_CHART_VERSION}" \
    --values "${REPO_ROOT}/platform/values-airflow.yaml" \
    --wait \
    --timeout 15m
}

install_ingress() {
  if [[ "${ENABLE_INGRESS}" != "true" ]]; then
    echo "Skipping ingress-nginx. Set ENABLE_INGRESS=true to install it."
    return
  fi

  log "Installing ingress-nginx into ${INGRESS_NAMESPACE}"
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace "${INGRESS_NAMESPACE}" \
    --create-namespace \
    --version "${INGRESS_NGINX_CHART_VERSION}" \
    --values "${REPO_ROOT}/platform/values-ingress-nginx.yaml" \
    --wait \
    --timeout 10m
}

install_monitoring() {
  if [[ "${ENABLE_MONITORING}" != "true" ]]; then
    echo "Skipping monitoring stack. Set ENABLE_MONITORING=true to install it."
    return
  fi

  log "Installing monitoring stack into ${MONITORING_NAMESPACE}"
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace "${MONITORING_NAMESPACE}" \
    --create-namespace \
    --reset-values \
    --version "${KUBE_PROMETHEUS_STACK_CHART_VERSION}" \
    --values "${REPO_ROOT}/platform/values-monitoring.yaml" \
    --wait \
    --timeout 15m
}

install_polaris() {
  if [[ "${ENABLE_POLARIS}" != "true" ]]; then
    echo "Skipping Polaris installation. Polaris is required by default; set ENABLE_POLARIS=false only for troubleshooting."
    return
  fi

  log "Creating Polaris persistence secret"
  kubectl create secret generic polaris-persistence \
    --namespace polaris \
    --from-literal=jdbcUrl="jdbc:postgresql://polaris-postgresql.polaris.svc.cluster.local:5432/polaris" \
    --from-literal=username="polaris" \
    --from-literal=password="${POLARIS_DB_PASSWORD}" \
    --from-literal=POSTGRES_DB="polaris" \
    --from-literal=POSTGRES_USER="polaris" \
    --from-literal=POSTGRES_PASSWORD="${POLARIS_DB_PASSWORD}" \
    --dry-run=client \
    --output yaml \
    | kubectl apply -f -

  log "Deploying Polaris PostgreSQL backing store"
  kubectl apply -f "${REPO_ROOT}/platform/polaris-postgresql.yaml"

  kubectl rollout status statefulset/polaris-postgresql \
    --namespace polaris \
    --timeout=10m

  log "Installing Polaris into polaris namespace using IRSA via polaris-sa"
  helm upgrade --install polaris polaris/polaris \
    --namespace polaris \
    --create-namespace \
    --devel \
    --reset-values \
    --version "${POLARIS_CHART_VERSION}" \
    --values "${REPO_ROOT}/platform/values-polaris.yaml" \
    --wait \
    --timeout 15m

  echo "Polaris service installed."
  echo "Catalog bootstrap is still a separate step after install."
}

main() {
  preflight
  add_helm_repos
  install_foundations
  install_strimzi
  install_spark_operator
  install_airflow
  install_ingress
  install_monitoring
  install_polaris

  echo "Platform services deployment completed."
  echo "Next steps: run platform/scripts/04-validate-platform.sh, then bootstrap Polaris if enabled."
}

main "$@"
