#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${TF_DIR:-${SCRIPT_DIR}}"
TF_PLAN_FILE="${TF_PLAN_FILE:-tfplan}"
BKP_DIR="${BKP_DIR:-${TF_DIR}/bkp}"

ACTION="plan"
YES="false"
AWS_REGION=""
AWS_ACCOUNT_ID=""
EKS_CLUSTER_NAME=""
LAKEHOUSE_BUCKET_NAME=""
EKS_CLUSTER_ROLE_NAME=""
EKS_NODE_ROLE_NAME=""
EBS_CSI_ROLE_NAME=""
POLARIS_S3_ROLE_NAME=""
SPARK_S3_ROLE_NAME=""
AIRFLOW_S3_ROLE_NAME=""
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage:
  deploy-infra.sh [--plan] [--apply] [--destroy] [--yes]

Behavior:
  --plan     Ensure required external AWS resources exist, then run terraform init/fmt/validate/plan. This is the default.
  --apply    Ensure required external AWS resources exist, bootstrap network and EKS control plane prerequisites, then run plan and apply.
  --destroy  Run terraform init and terraform plan -destroy. With --yes, also run terraform destroy.
  --yes      Skip the confirmation prompt for --apply or the second confirmation for --destroy.

Notes:
  - This script checks and reuses the shared IAM roles and lakehouse bucket if they already exist.
  - If they do not exist, this script creates them before Terraform runs.
  - Terraform does not own those shared IAM roles or the bucket, so destroy will not remove them.

Environment:
  TF_DIR         Terraform environment directory.
  TF_PLAN_FILE   Terraform plan output file name.
  BKP_DIR        Directory used for timestamped Terraform state backups after successful apply.
EOF
}

confirm() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N]: " answer
  [[ "${answer}" =~ ^[Yy]$ ]]
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

cleanup_tmp_dir() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
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
  ' "${TF_DIR}/terraform.tfvars"
}

aws_cli() {
  aws --region "${AWS_REGION}" "$@"
}

terraform_cmd() {
  terraform -chdir="${TF_DIR}" "$@"
}

log() {
  printf '[aws-proto] %s\n' "$*"
}

backup_state_files() {
  local timestamp state_file backup_file state_copy backup_copy

  state_file="${TF_DIR}/terraform.tfstate"
  backup_file="${TF_DIR}/terraform.tfstate.backup"

  if [[ ! -f "${state_file}" ]]; then
    log "Terraform state file not found at ${state_file}; skipping backup"
    return
  fi

  mkdir -p "${BKP_DIR}"
  timestamp="$(date +%Y-%m-%d-%H%M%S)"

  state_copy="${BKP_DIR}/terraform.tfstate.${timestamp}"
  cp "${state_file}" "${state_copy}"
  log "Terraform state backup created: ${state_copy}"

  if [[ -f "${backup_file}" ]]; then
    backup_copy="${BKP_DIR}/terraform.tfstate.backup.${timestamp}"
    cp "${backup_file}" "${backup_copy}"
    log "Terraform backup state copy created: ${backup_copy}"
  fi
}

role_exists() {
  aws iam get-role --role-name "$1" >/dev/null 2>&1
}

bucket_exists() {
  aws s3api head-bucket --bucket "$1" >/dev/null 2>&1
}

bucket_owned_by_current_account() {
  local bucket_name="$1"
  aws s3api list-buckets \
    --query "Buckets[?Name=='${bucket_name}'].Name" \
    --output text 2>/dev/null | grep -Fxq "${bucket_name}"
}

create_role() {
  local role_name="$1"
  local trust_policy_file="$2"

  aws iam create-role \
    --role-name "${role_name}" \
    --assume-role-policy-document "$(cat "${trust_policy_file}")" \
    --tags "Key=Name,Value=${role_name}" "Key=Project,Value=dc-platform-bss" "Key=Environment,Value=proto" "Key=ManagedBy,Value=aws-cli" \
    >/dev/null
}

attach_managed_policy() {
  local role_name="$1"
  local policy_arn="$2"
  log "Attaching policy ${policy_arn} to ${role_name}"
  aws iam attach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}" >/dev/null
}

put_inline_policy() {
  local role_name="$1"
  local policy_name="$2"
  local policy_file="$3"
  log "Attaching inline policy ${policy_name} to ${role_name}"
  aws iam put-role-policy --role-name "${role_name}" --policy-name "${policy_name}" --policy-document "$(cat "${policy_file}")" >/dev/null
}

write_placeholder_trust_policy() {
  local output_file="$1"
  cat >"${output_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

write_lakehouse_s3_policy() {
  local output_file="$1"
  cat >"${output_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": "arn:aws:s3:::${LAKEHOUSE_BUCKET_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${LAKEHOUSE_BUCKET_NAME}/*"
    }
  ]
}
EOF
}

write_bucket_tagging() {
  local output_file="$1"
  cat >"${output_file}" <<EOF
{
  "TagSet": [
    {"Key": "Name", "Value": "${LAKEHOUSE_BUCKET_NAME}"},
    {"Key": "Project", "Value": "dc-platform-bss"},
    {"Key": "Environment", "Value": "proto"},
    {"Key": "ManagedBy", "Value": "aws-cli"}
  ]
}
EOF
}

ensure_role_exists_or_create() {
  local role_name="$1"
  local trust_policy_file="$2"
  local mode="$3"

  log "Checking IAM role ${role_name}"
  if role_exists "${role_name}"; then
    log "Using existing IAM role ${role_name}"
    if [[ "${mode}" == "lakehouse-s3" ]]; then
      # Keep shared Spark/Airflow/Polaris S3 roles aligned when the bucket name changes.
      put_inline_policy "${role_name}" "dc-platform-bss-lakehouse-s3-access" "${TMP_DIR}/lakehouse-s3-policy.json"
    fi
    return 0
  fi

  log "IAM role ${role_name} not found"
  log "Creating IAM role ${role_name}"
  create_role "${role_name}" "${trust_policy_file}"

  case "${mode}" in
    eks-cluster)
      attach_managed_policy "${role_name}" "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
      ;;
    eks-node)
      attach_managed_policy "${role_name}" "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
      attach_managed_policy "${role_name}" "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
      attach_managed_policy "${role_name}" "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
      ;;
    ebs-csi)
      attach_managed_policy "${role_name}" "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      ;;
    lakehouse-s3)
      put_inline_policy "${role_name}" "dc-platform-bss-lakehouse-s3-access" "${TMP_DIR}/lakehouse-s3-policy.json"
      ;;
  esac
}

create_bucket() {
  log "Creating S3 bucket ${LAKEHOUSE_BUCKET_NAME}"
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    if ! aws s3api create-bucket --bucket "${LAKEHOUSE_BUCKET_NAME}" >/dev/null 2>"${TMP_DIR}/create-bucket.stderr"; then
      if grep -q "BucketAlreadyOwnedByYou" "${TMP_DIR}/create-bucket.stderr"; then
        log "Using existing S3 bucket ${LAKEHOUSE_BUCKET_NAME}"
        return 0
      fi
      cat "${TMP_DIR}/create-bucket.stderr" >&2
      return 1
    fi
  else
    if ! aws s3api create-bucket \
      --bucket "${LAKEHOUSE_BUCKET_NAME}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" \
      >/dev/null 2>"${TMP_DIR}/create-bucket.stderr"; then
      if grep -q "BucketAlreadyOwnedByYou" "${TMP_DIR}/create-bucket.stderr"; then
        log "Using existing S3 bucket ${LAKEHOUSE_BUCKET_NAME}"
        return 0
      fi
      cat "${TMP_DIR}/create-bucket.stderr" >&2
      return 1
    fi
  fi

  log "Configuring public access block for ${LAKEHOUSE_BUCKET_NAME}"
  aws s3api put-public-access-block \
    --bucket "${LAKEHOUSE_BUCKET_NAME}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
    >/dev/null

  log "Configuring bucket encryption for ${LAKEHOUSE_BUCKET_NAME}"
  aws s3api put-bucket-encryption \
    --bucket "${LAKEHOUSE_BUCKET_NAME}" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    >/dev/null

  log "Enabling versioning for ${LAKEHOUSE_BUCKET_NAME}"
  aws s3api put-bucket-versioning \
    --bucket "${LAKEHOUSE_BUCKET_NAME}" \
    --versioning-configuration Status=Enabled \
    >/dev/null

  log "Tagging bucket ${LAKEHOUSE_BUCKET_NAME}"
  aws s3api put-bucket-tagging \
    --bucket "${LAKEHOUSE_BUCKET_NAME}" \
    --tagging "$(cat "${TMP_DIR}/bucket-tagging.json")" \
    >/dev/null
}

ensure_bucket_exists_or_create() {
  log "Checking S3 bucket ${LAKEHOUSE_BUCKET_NAME}"
  if bucket_owned_by_current_account "${LAKEHOUSE_BUCKET_NAME}"; then
    log "Using existing S3 bucket ${LAKEHOUSE_BUCKET_NAME}"
    return 0
  fi

  if bucket_exists "${LAKEHOUSE_BUCKET_NAME}"; then
    echo "S3 bucket ${LAKEHOUSE_BUCKET_NAME} already exists but is not owned by the current AWS account." >&2
    echo "Choose a different bucket name in terraform.tfvars or switch to the owning account." >&2
    exit 1
  fi

  log "S3 bucket ${LAKEHOUSE_BUCKET_NAME} not found"
  create_bucket
}

load_external_inputs() {
  if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
    echo "terraform tfvars file not found: ${TF_DIR}/terraform.tfvars" >&2
    exit 1
  fi

  AWS_REGION="$(read_tfvar aws_region)"
  EKS_CLUSTER_NAME="$(read_tfvar eks_cluster_name)"
  LAKEHOUSE_BUCKET_NAME="$(read_tfvar lakehouse_bucket_name)"
  EKS_CLUSTER_ROLE_NAME="$(read_tfvar eks_cluster_role_name)"
  EKS_NODE_ROLE_NAME="$(read_tfvar eks_node_role_name)"
  EBS_CSI_ROLE_NAME="$(read_tfvar ebs_csi_role_name)"
  POLARIS_S3_ROLE_NAME="$(read_tfvar polaris_s3_role_name)"
  SPARK_S3_ROLE_NAME="$(read_tfvar spark_s3_role_name)"
  AIRFLOW_S3_ROLE_NAME="$(read_tfvar airflow_s3_role_name)"

  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
}

cluster_exists() {
  aws eks describe-cluster --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1
}

get_cluster_oidc_issuer() {
  aws eks describe-cluster \
    --region "${AWS_REGION}" \
    --name "${EKS_CLUSTER_NAME}" \
    --query 'cluster.identity.oidc.issuer' \
    --output text 2>/dev/null
}

ensure_external_resources() {
  require_cmd aws
  load_external_inputs

  log "Preparing external AWS dependencies before Terraform"
  TMP_DIR="$(mktemp -d)"
  trap cleanup_tmp_dir EXIT

  cat >"${TMP_DIR}/eks-cluster-trust.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  cat >"${TMP_DIR}/eks-node-trust.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  write_placeholder_trust_policy "${TMP_DIR}/placeholder-trust.json"
  write_lakehouse_s3_policy "${TMP_DIR}/lakehouse-s3-policy.json"
  write_bucket_tagging "${TMP_DIR}/bucket-tagging.json"

  ensure_role_exists_or_create "${EKS_CLUSTER_ROLE_NAME}" "${TMP_DIR}/eks-cluster-trust.json" "eks-cluster"
  ensure_role_exists_or_create "${EKS_NODE_ROLE_NAME}" "${TMP_DIR}/eks-node-trust.json" "eks-node"
  ensure_role_exists_or_create "${EBS_CSI_ROLE_NAME}" "${TMP_DIR}/placeholder-trust.json" "ebs-csi"
  ensure_role_exists_or_create "${POLARIS_S3_ROLE_NAME}" "${TMP_DIR}/placeholder-trust.json" "lakehouse-s3"
  ensure_role_exists_or_create "${SPARK_S3_ROLE_NAME}" "${TMP_DIR}/placeholder-trust.json" "lakehouse-s3"
  ensure_role_exists_or_create "${AIRFLOW_S3_ROLE_NAME}" "${TMP_DIR}/placeholder-trust.json" "lakehouse-s3"
  ensure_bucket_exists_or_create

  trap - EXIT
  cleanup_tmp_dir
  TMP_DIR=""
}

update_irsa_trust_policy() {
  local role_name="$1"
  local oidc_provider_host="$2"
  local namespace="$3"
  local service_account="$4"
  local trust_policy_file="$5"

  cat >"${trust_policy_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${oidc_provider_host}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_provider_host}:aud": "sts.amazonaws.com",
          "${oidc_provider_host}:sub": "system:serviceaccount:${namespace}:${service_account}"
        }
      }
    }
  ]
}
EOF

  log "Updating trust policy for ${role_name}"
  aws iam update-assume-role-policy --role-name "${role_name}" --policy-document "$(cat "${trust_policy_file}")" >/dev/null
}

update_irsa_trust_policies_after_apply() {
  load_external_inputs

  local oidc_issuer oidc_provider_host
  log "Reading cluster OIDC issuer from the EKS control plane"
  oidc_issuer="$(get_cluster_oidc_issuer)"
  oidc_provider_host="${oidc_issuer#https://}"

  TMP_DIR="$(mktemp -d)"
  trap cleanup_tmp_dir EXIT

  update_irsa_trust_policy "${EBS_CSI_ROLE_NAME}" "${oidc_provider_host}" "kube-system" "ebs-csi-controller-sa" "${TMP_DIR}/ebs-csi-trust.json"
  update_irsa_trust_policy "${POLARIS_S3_ROLE_NAME}" "${oidc_provider_host}" "polaris" "polaris-sa" "${TMP_DIR}/polaris-trust.json"
  update_irsa_trust_policy "${SPARK_S3_ROLE_NAME}" "${oidc_provider_host}" "spark" "spark-sa" "${TMP_DIR}/spark-trust.json"
  update_irsa_trust_policy "${AIRFLOW_S3_ROLE_NAME}" "${oidc_provider_host}" "airflow" "airflow-sa" "${TMP_DIR}/airflow-trust.json"

  trap - EXIT
  cleanup_tmp_dir
  TMP_DIR=""
}

bootstrap_cluster_for_irsa() {
  load_external_inputs

  log "Bootstrapping VPC, subnets, routing, and NAT before cluster/node creation"
  terraform_cmd apply -target=module.vpc -auto-approve

  if cluster_exists; then
    local existing_oidc
    existing_oidc="$(get_cluster_oidc_issuer)"
    if [[ -n "${existing_oidc}" && "${existing_oidc}" != "None" ]]; then
      log "EKS cluster ${EKS_CLUSTER_NAME} already exists; updating IRSA trust before full apply"
      update_irsa_trust_policies_after_apply
      return
    fi
  fi

  log "Bootstrapping EKS control plane before node groups and addons"
  terraform_cmd apply -target=module.eks.aws_eks_cluster.this[0] -auto-approve
  update_irsa_trust_policies_after_apply
}

prepare_terraform() {
  local fmt_mode="${1:-check}"
  ensure_external_resources
  log "Running terraform init in ${TF_DIR}"
  terraform_cmd init
  if [[ "${fmt_mode}" == "write" ]]; then
    log "Running terraform fmt"
    terraform_cmd fmt -recursive
  else
    log "Checking terraform formatting"
    terraform_cmd fmt -check -recursive
  fi
  log "Running terraform validate"
  terraform_cmd validate
}

run_plan_flow() {
  prepare_terraform check
  log "Running terraform plan"
  terraform_cmd plan -out="${TF_PLAN_FILE}"
}

run_destroy_flow() {
  local destroy_plan_file="${TF_PLAN_FILE}-destroy"

  log "Running terraform init in ${TF_DIR}"
  terraform_cmd init
  log "Running terraform destroy plan"
  terraform_cmd plan -destroy -out="${destroy_plan_file}"

  if [[ "${YES}" != "true" ]]; then
    echo "Destroy will remove Terraform-managed AWS infrastructure and stop ongoing charges."
    echo "Shared IAM roles and the external lakehouse bucket are not destroyed by this workflow."
    if ! confirm "Proceed with terraform destroy?"; then
      echo "Destroy cancelled."
      exit 0
    fi
  fi

  log "Applying terraform destroy plan"
  terraform_cmd apply "${destroy_plan_file}"
}

main() {
  require_cmd terraform

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan)
        ACTION="plan"
        ;;
      --apply)
        ACTION="apply"
        ;;
      --destroy)
        ACTION="destroy"
        ;;
      --yes)
        YES="true"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  case "${ACTION}" in
    plan)
      run_plan_flow
      log "Terraform plan completed in ${TF_DIR}"
      ;;
    apply)
      prepare_terraform write
      bootstrap_cluster_for_irsa
      log "Running terraform plan"
      terraform_cmd plan -out="${TF_PLAN_FILE}"
      if [[ "${YES}" != "true" ]]; then
        if ! confirm "Apply the generated terraform plan now?"; then
          echo "Apply cancelled. The plan file remains at ${TF_DIR}/${TF_PLAN_FILE}."
          exit 0
        fi
      fi
      log "Applying terraform plan"
      terraform_cmd apply "${TF_PLAN_FILE}"
      update_irsa_trust_policies_after_apply
      backup_state_files
      log "Terraform apply completed"
      ;;
    destroy)
      run_destroy_flow
      log "Terraform destroy completed"
      ;;
  esac
}

main "$@"
