#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TFVARS_FILE="${TFVARS_FILE:-${REPO_ROOT}/infra/aws-proto/terraform.tfvars}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

read_tfvar() {
  local key="$1"
  awk -F '=' -v wanted="${key}" '
    $1 ~ "^[[:space:]]*" wanted "[[:space:]]*$" {
      value=$2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
  ' "${TFVARS_FILE}"
}

main() {
  require_cmd aws

  if [[ ! -f "${TFVARS_FILE}" ]]; then
    echo "terraform tfvars file not found: ${TFVARS_FILE}" >&2
    exit 1
  fi

  local region cluster_name
  region="${AWS_REGION_OVERRIDE:-$(read_tfvar aws_region)}"
  cluster_name="${EKS_CLUSTER_NAME_OVERRIDE:-$(read_tfvar eks_cluster_name)}"

  if [[ -z "${region}" || -z "${cluster_name}" ]]; then
    echo "unable to determine aws_region or eks_cluster_name from ${TFVARS_FILE}" >&2
    exit 1
  fi

  aws eks update-kubeconfig --region "${region}" --name "${cluster_name}"
  echo "kubeconfig updated for cluster ${cluster_name} in ${region}."
}

main "$@"
