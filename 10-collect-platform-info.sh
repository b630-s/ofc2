#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${TF_DIR:-${REPO_ROOT}/infra/aws-proto}"
TFVARS_FILE="${TFVARS_FILE:-${TF_DIR}/terraform.tfvars}"
CONFIG_DIR="${REPO_ROOT}/reference-workloads/config"
PLATFORM_CONFIG_ENV="${CONFIG_DIR}/platform-config.env"
PLATFORM_SECRETS_ENV="${CONFIG_DIR}/platform-secrets.env"

KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-kafka}"
KAFKA_BOOTSTRAP_SERVICE="${KAFKA_BOOTSTRAP_SERVICE:-reference-kafka-kafka-bootstrap}"
KAFKA_BOOTSTRAP_PORT="${KAFKA_BOOTSTRAP_PORT:-9092}"
KAFKA_CLIENT_POD="${KAFKA_CLIENT_POD:-kafka-test-client}"
KAFKA_TOPIC="${KAFKA_TOPIC:-orders_raw}"
KAFKA_DLQ_TOPIC="${KAFKA_DLQ_TOPIC:-orders_dlq}"
SPARK_NAMESPACE="${SPARK_NAMESPACE:-spark}"
SPARK_SERVICE_ACCOUNT="${SPARK_SERVICE_ACCOUNT:-spark-sa}"
SPARK_NODE_SELECTOR_GROUP="${SPARK_NODE_SELECTOR_GROUP:-workload}"
POLARIS_NAMESPACE="${POLARIS_NAMESPACE:-polaris}"
POLARIS_SERVICE="${POLARIS_SERVICE:-polaris}"
POLARIS_SECRET_NAME="${POLARIS_SECRET_NAME:-reference-polaris-spark-credentials}"
REFERENCE_CATALOG="${REFERENCE_CATALOG:-reference}"
REFERENCE_BASE_PREFIX="${REFERENCE_BASE_PREFIX:-reference}"
POLARIS_USER_CLIENT_ID="${POLARIS_USER_CLIENT_ID:-}"
POLARIS_USER_CLIENT_SECRET="${POLARIS_USER_CLIENT_SECRET:-}"
REFERENCE_SPARK_IMAGE="${REFERENCE_SPARK_IMAGE:-}"
LAKEHOUSE_BUCKET="${LAKEHOUSE_BUCKET:-}"
AWS_REGION="${AWS_REGION:-}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
SPARK_S3_ROLE_ARN="${SPARK_S3_ROLE_ARN:-}"
AIRFLOW_S3_ROLE_ARN="${AIRFLOW_S3_ROLE_ARN:-}"
POLARIS_S3_ROLE_ARN="${POLARIS_S3_ROLE_ARN:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[collect-platform-info] %s\n' "$*"
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

resolve_tfvar_string() {
  local key="$1"

  if [[ ! -f "${TFVARS_FILE}" ]]; then
    return 1
  fi

  sed -n "s/^${key}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\"[[:space:]]*$/\\1/p" "${TFVARS_FILE}" | head -n 1
}

backup_if_exists() {
  local file_path="$1"
  local timestamp="$2"

  if [[ -f "${file_path}" ]]; then
    cp "${file_path}" "${file_path}.bak.${timestamp}"
    log "Backed up $(basename "${file_path}") to $(basename "${file_path}.bak.${timestamp}")"
  fi
}

shell_quote() {
  printf '%q' "$1"
}

write_env_var() {
  local key="$1"
  local value="$2"

  printf '%s=%s\n' "${key}" "$(shell_quote "${value}")"
}

resolve_platform_values() {
  if [[ -z "${LAKEHOUSE_BUCKET}" ]]; then
    LAKEHOUSE_BUCKET="$(resolve_tf_output lakehouse_bucket_name || true)"
  fi

  if [[ -z "${EKS_CLUSTER_NAME}" ]]; then
    EKS_CLUSTER_NAME="$(resolve_tf_output eks_cluster_name || true)"
  fi

  if [[ -z "${SPARK_S3_ROLE_ARN}" ]]; then
    SPARK_S3_ROLE_ARN="$(resolve_tf_output spark_s3_role_arn || true)"
  fi

  if [[ -z "${AIRFLOW_S3_ROLE_ARN}" ]]; then
    AIRFLOW_S3_ROLE_ARN="$(resolve_tf_output airflow_s3_role_arn || true)"
  fi

  if [[ -z "${POLARIS_S3_ROLE_ARN}" ]]; then
    POLARIS_S3_ROLE_ARN="$(resolve_tf_output polaris_s3_role_arn || true)"
  fi

  if [[ -z "${AWS_REGION}" ]]; then
    AWS_REGION="${AWS_DEFAULT_REGION:-}"
  fi

  if [[ -z "${AWS_REGION}" ]]; then
    AWS_REGION="$(resolve_tfvar_string aws_region || true)"
  fi

  if [[ -z "${AWS_REGION}" ]] && command -v aws >/dev/null 2>&1; then
    AWS_REGION="$(aws configure get region 2>/dev/null || true)"
  fi

  KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVICE}.${KAFKA_NAMESPACE}.svc.cluster.local:${KAFKA_BOOTSTRAP_PORT}"
  POLARIS_CATALOG_URI="http://${POLARIS_SERVICE}.${POLARIS_NAMESPACE}.svc.cluster.local:8181/api/catalog"

  if [[ -n "${LAKEHOUSE_BUCKET}" ]]; then
    REFERENCE_BASE_PATH="s3a://${LAKEHOUSE_BUCKET}/${REFERENCE_BASE_PREFIX}"
    SPARK_EVENT_LOG_DIR="${REFERENCE_BASE_PATH}/spark-event-logs"
    ORDERS_RAW_PATH="${ORDERS_RAW_PATH:-${REFERENCE_BASE_PATH}/raw/orders/}"
    ORDERS_CURATED_PATH="${ORDERS_CURATED_PATH:-${REFERENCE_BASE_PATH}/curated/orders/}"
    ORDERS_ICEBERG_TABLE="${ORDERS_ICEBERG_TABLE:-${REFERENCE_CATALOG}.bronze.orders_raw}"
  else
    REFERENCE_BASE_PATH=""
    SPARK_EVENT_LOG_DIR=""
  fi
}

resolve_runtime_secrets() {
  if [[ -n "${POLARIS_USER_CLIENT_ID}" && -n "${POLARIS_USER_CLIENT_SECRET}" ]]; then
    return 0
  fi

  if ! kubectl get secret "${POLARIS_SECRET_NAME}" -n "${SPARK_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -z "${POLARIS_USER_CLIENT_ID}" ]]; then
    POLARIS_USER_CLIENT_ID="$(
      kubectl get secret "${POLARIS_SECRET_NAME}" -n "${SPARK_NAMESPACE}" \
        -o jsonpath='{.data.client-id}' 2>/dev/null | base64 --decode
    )"
  fi

  if [[ -z "${POLARIS_USER_CLIENT_SECRET}" ]]; then
    POLARIS_USER_CLIENT_SECRET="$(
      kubectl get secret "${POLARIS_SECRET_NAME}" -n "${SPARK_NAMESPACE}" \
        -o jsonpath='{.data.client-secret}' 2>/dev/null | base64 --decode
    )"
  fi
}

write_platform_config() {
  cat > "${PLATFORM_CONFIG_ENV}" <<EOF
# Generated by platform/scripts/10-collect-platform-info.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Share this file with workload developers as the non-sensitive platform handoff.
EOF

  {
    write_env_var KAFKA_NAMESPACE "${KAFKA_NAMESPACE}"
    write_env_var KAFKA_BOOTSTRAP_SERVICE "${KAFKA_BOOTSTRAP_SERVICE}"
    write_env_var KAFKA_BOOTSTRAP_PORT "${KAFKA_BOOTSTRAP_PORT}"
    write_env_var KAFKA_BOOTSTRAP_SERVER "${KAFKA_BOOTSTRAP_SERVER}"
    write_env_var KAFKA_CLIENT_POD "${KAFKA_CLIENT_POD}"
    write_env_var KAFKA_TOPIC "${KAFKA_TOPIC}"
    write_env_var KAFKA_DLQ_TOPIC "${KAFKA_DLQ_TOPIC}"
    write_env_var SPARK_NAMESPACE "${SPARK_NAMESPACE}"
    write_env_var SPARK_SERVICE_ACCOUNT "${SPARK_SERVICE_ACCOUNT}"
    write_env_var SPARK_NODE_SELECTOR_GROUP "${SPARK_NODE_SELECTOR_GROUP}"
    write_env_var POLARIS_NAMESPACE "${POLARIS_NAMESPACE}"
    write_env_var POLARIS_SERVICE "${POLARIS_SERVICE}"
    write_env_var POLARIS_CATALOG_URI "${POLARIS_CATALOG_URI}"
    write_env_var POLARIS_SECRET_NAME "${POLARIS_SECRET_NAME}"
    write_env_var REFERENCE_CATALOG "${REFERENCE_CATALOG}"
    write_env_var REFERENCE_BASE_PREFIX "${REFERENCE_BASE_PREFIX}"
    if [[ -n "${REFERENCE_BASE_PATH}" ]]; then
      write_env_var REFERENCE_BASE_PATH "${REFERENCE_BASE_PATH}"
    fi
    if [[ -n "${SPARK_EVENT_LOG_DIR}" ]]; then
      write_env_var SPARK_EVENT_LOG_DIR "${SPARK_EVENT_LOG_DIR}"
    fi
    if [[ -n "${ORDERS_RAW_PATH:-}" ]]; then
      write_env_var ORDERS_RAW_PATH "${ORDERS_RAW_PATH}"
    fi
    if [[ -n "${ORDERS_CURATED_PATH:-}" ]]; then
      write_env_var ORDERS_CURATED_PATH "${ORDERS_CURATED_PATH}"
    fi
    if [[ -n "${ORDERS_ICEBERG_TABLE:-}" ]]; then
      write_env_var ORDERS_ICEBERG_TABLE "${ORDERS_ICEBERG_TABLE}"
    fi
    if [[ -n "${LAKEHOUSE_BUCKET}" ]]; then
      write_env_var LAKEHOUSE_BUCKET "${LAKEHOUSE_BUCKET}"
    fi
    if [[ -n "${AWS_REGION}" ]]; then
      write_env_var AWS_REGION "${AWS_REGION}"
    fi
    if [[ -n "${EKS_CLUSTER_NAME}" ]]; then
      write_env_var EKS_CLUSTER_NAME "${EKS_CLUSTER_NAME}"
    fi
    if [[ -n "${SPARK_S3_ROLE_ARN}" ]]; then
      write_env_var SPARK_S3_ROLE_ARN "${SPARK_S3_ROLE_ARN}"
    fi
    if [[ -n "${AIRFLOW_S3_ROLE_ARN}" ]]; then
      write_env_var AIRFLOW_S3_ROLE_ARN "${AIRFLOW_S3_ROLE_ARN}"
    fi
    if [[ -n "${POLARIS_S3_ROLE_ARN}" ]]; then
      write_env_var POLARIS_S3_ROLE_ARN "${POLARIS_S3_ROLE_ARN}"
    fi
    if [[ -n "${REFERENCE_SPARK_IMAGE}" ]]; then
      write_env_var REFERENCE_SPARK_IMAGE "${REFERENCE_SPARK_IMAGE}"
    else
      printf '# REFERENCE_SPARK_IMAGE=  # Set after building and pushing the workload image\n'
      printf '# Airflow Variable to seed: reference_spark_image=<same value>\n'
    fi
  } >> "${PLATFORM_CONFIG_ENV}"
}

write_platform_secrets() {
  cat > "${PLATFORM_SECRETS_ENV}" <<EOF
# Generated by platform/scripts/10-collect-platform-info.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Keep this file out of version control and share it only through a secure channel.
EOF

  if [[ -n "${POLARIS_USER_CLIENT_ID}" && -n "${POLARIS_USER_CLIENT_SECRET}" ]]; then
    {
      write_env_var POLARIS_USER_CLIENT_ID "${POLARIS_USER_CLIENT_ID}"
      write_env_var POLARIS_USER_CLIENT_SECRET "${POLARIS_USER_CLIENT_SECRET}"
    } >> "${PLATFORM_SECRETS_ENV}"
    log "Wrote runtime Polaris credentials to reference-workloads/config/platform-secrets.env"
    return
  fi

  cat >> "${PLATFORM_SECRETS_ENV}" <<'EOF'
# Polaris runtime credentials were not available when this file was generated.
# Re-run this script after the runtime secret exists, or export
# POLARIS_USER_CLIENT_ID and POLARIS_USER_CLIENT_SECRET before running it.
EOF

  log "Secrets file created without Polaris runtime credentials"
}

preflight() {
  require_cmd kubectl
  require_cmd base64

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not connected to a cluster. Run dc-platform/platform/scripts/02-connect-cluster.sh first." >&2
    exit 1
  fi
}

main() {
  local timestamp

  preflight
  mkdir -p "${CONFIG_DIR}"

  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  backup_if_exists "${PLATFORM_CONFIG_ENV}" "${timestamp}"
  backup_if_exists "${PLATFORM_SECRETS_ENV}" "${timestamp}"

  resolve_platform_values
  resolve_runtime_secrets
  write_platform_config
  write_platform_secrets

  log "Generated reference-workloads/config/platform-config.env"
  log "Developers can override generated values in reference-workloads/config/platform-config.local.env"
  if [[ -n "${REFERENCE_SPARK_IMAGE}" ]]; then
    log "Airflow Variable to seed manually: reference_spark_image=${REFERENCE_SPARK_IMAGE}"
  else
    log "Airflow Variable to seed manually after image publish: reference_spark_image=<REFERENCE_SPARK_IMAGE>"
  fi
}

main "$@"
