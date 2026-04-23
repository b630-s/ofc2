#!/usr/bin/env bash
# dc-platform-bss smoke test script marker: v2026-04-23a

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${STATE_FILE:-${SCRIPT_DIR}/.aws-access-smoke-test.env}"

ACTION="create"

TEST_NAME="${TEST_NAME:-dc-platform-bss-access-smoke}"
NAME_PREFIX="dc-platform-bss-"
PROJECT_TAG="dc-platform-bss"
SCRIPT_VERSION="v2026-04-23a"
AWS_REGION="${AWS_REGION:-}"
CLUSTER_VERSION="${CLUSTER_VERSION:-1.34}"
NODE_INSTANCE_TYPE="${NODE_INSTANCE_TYPE:-t3.small}"
NODE_DISK_SIZE="${NODE_DISK_SIZE:-20}"

VPC_CIDR="${VPC_CIDR:-10.250.0.0/16}"
PUBLIC_SUBNET_1_CIDR="${PUBLIC_SUBNET_1_CIDR:-10.250.101.0/24}"
PUBLIC_SUBNET_2_CIDR="${PUBLIC_SUBNET_2_CIDR:-10.250.102.0/24}"
PRIVATE_SUBNET_1_CIDR="${PRIVATE_SUBNET_1_CIDR:-10.250.1.0/24}"
PRIVATE_SUBNET_2_CIDR="${PRIVATE_SUBNET_2_CIDR:-10.250.2.0/24}"

EKS_CLUSTER_NAME=""
NODEGROUP_NAME=""
CLUSTER_ROLE_NAME=""
NODE_ROLE_NAME=""
EBS_CSI_ROLE_NAME=""
LOG_GROUP_NAME=""

VPC_ID=""
INTERNET_GATEWAY_ID=""
PUBLIC_ROUTE_TABLE_ID=""
PRIVATE_ROUTE_TABLE_ID=""
PUBLIC_ROUTE_ASSOC_1_ID=""
PUBLIC_ROUTE_ASSOC_2_ID=""
PRIVATE_ROUTE_ASSOC_1_ID=""
PRIVATE_ROUTE_ASSOC_2_ID=""
PUBLIC_SUBNET_1_ID=""
PUBLIC_SUBNET_2_ID=""
PRIVATE_SUBNET_1_ID=""
PRIVATE_SUBNET_2_ID=""
ELASTIC_IP_ALLOCATION_ID=""
NAT_GATEWAY_ID=""

AZ_1=""
AZ_2=""

CLUSTER_ROLE_ARN=""
NODE_ROLE_ARN=""
OIDC_ISSUER=""
OIDC_PROVIDER_HOST=""
OIDC_PROVIDER_ARN=""
EBS_CSI_ROLE_ARN=""
PROVIDED_CLUSTER_ROLE_ARN="${PROVIDED_CLUSTER_ROLE_ARN:-}"
PROVIDED_NODE_ROLE_ARN="${PROVIDED_NODE_ROLE_ARN:-}"

TMP_DIR=""

usage() {
  cat <<'EOF'
Usage:
  00-aws-access-smoke-test.sh [create|status|destroy] [--region REGION] [--name NAME]

Purpose:
  Create the smallest practical AWS smoke-test environment that exercises the same
  AWS permission families as the real Terraform deployment:
  - VPC, subnets, routes, internet gateway, NAT gateway, and elastic IP
  - IAM roles for EKS and worker nodes
  - EKS cluster, managed node group, OIDC provider, and EBS CSI addon

Defaults:
  action               create
  cluster version      1.34
  node type            t3.small
  node disk            20 GiB
  state file           scripts/.aws-access-smoke-test.env

Examples:
  ./scripts/00-aws-access-smoke-test.sh create --region us-east-1
  ./scripts/00-aws-access-smoke-test.sh status
  ./scripts/00-aws-access-smoke-test.sh destroy

Notes:
  - This script creates billable AWS resources, including EKS and NAT Gateway.
  - Destroy the smoke test when you are finished.
  - All created resource names are forced to start with the prefix dc-platform-bss-.
EOF
}

log() {
  printf '[smoke-test] %s\n' "$*"
}

die() {
  printf '[smoke-test] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "missing required command: $1"
  fi
}

aws_cli() {
  aws --region "${AWS_REGION}" "$@"
}

cleanup_tmp_dir() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}

write_state() {
  cat >"${STATE_FILE}" <<EOF
TEST_NAME="${TEST_NAME}"
AWS_REGION="${AWS_REGION}"
CLUSTER_VERSION="${CLUSTER_VERSION}"
NODE_INSTANCE_TYPE="${NODE_INSTANCE_TYPE}"
NODE_DISK_SIZE="${NODE_DISK_SIZE}"
PROVIDED_CLUSTER_ROLE_ARN="${PROVIDED_CLUSTER_ROLE_ARN}"
PROVIDED_NODE_ROLE_ARN="${PROVIDED_NODE_ROLE_ARN}"
VPC_CIDR="${VPC_CIDR}"
PUBLIC_SUBNET_1_CIDR="${PUBLIC_SUBNET_1_CIDR}"
PUBLIC_SUBNET_2_CIDR="${PUBLIC_SUBNET_2_CIDR}"
PRIVATE_SUBNET_1_CIDR="${PRIVATE_SUBNET_1_CIDR}"
PRIVATE_SUBNET_2_CIDR="${PRIVATE_SUBNET_2_CIDR}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}"
NODEGROUP_NAME="${NODEGROUP_NAME}"
CLUSTER_ROLE_NAME="${CLUSTER_ROLE_NAME}"
NODE_ROLE_NAME="${NODE_ROLE_NAME}"
EBS_CSI_ROLE_NAME="${EBS_CSI_ROLE_NAME}"
LOG_GROUP_NAME="${LOG_GROUP_NAME}"
VPC_ID="${VPC_ID}"
INTERNET_GATEWAY_ID="${INTERNET_GATEWAY_ID}"
PUBLIC_ROUTE_TABLE_ID="${PUBLIC_ROUTE_TABLE_ID}"
PRIVATE_ROUTE_TABLE_ID="${PRIVATE_ROUTE_TABLE_ID}"
PUBLIC_ROUTE_ASSOC_1_ID="${PUBLIC_ROUTE_ASSOC_1_ID}"
PUBLIC_ROUTE_ASSOC_2_ID="${PUBLIC_ROUTE_ASSOC_2_ID}"
PRIVATE_ROUTE_ASSOC_1_ID="${PRIVATE_ROUTE_ASSOC_1_ID}"
PRIVATE_ROUTE_ASSOC_2_ID="${PRIVATE_ROUTE_ASSOC_2_ID}"
PUBLIC_SUBNET_1_ID="${PUBLIC_SUBNET_1_ID}"
PUBLIC_SUBNET_2_ID="${PUBLIC_SUBNET_2_ID}"
PRIVATE_SUBNET_1_ID="${PRIVATE_SUBNET_1_ID}"
PRIVATE_SUBNET_2_ID="${PRIVATE_SUBNET_2_ID}"
ELASTIC_IP_ALLOCATION_ID="${ELASTIC_IP_ALLOCATION_ID}"
NAT_GATEWAY_ID="${NAT_GATEWAY_ID}"
AZ_1="${AZ_1}"
AZ_2="${AZ_2}"
CLUSTER_ROLE_ARN="${CLUSTER_ROLE_ARN}"
NODE_ROLE_ARN="${NODE_ROLE_ARN}"
OIDC_ISSUER="${OIDC_ISSUER}"
OIDC_PROVIDER_HOST="${OIDC_PROVIDER_HOST}"
OIDC_PROVIDER_ARN="${OIDC_PROVIDER_ARN}"
EBS_CSI_ROLE_ARN="${EBS_CSI_ROLE_ARN}"
EOF
}

load_state() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    die "state file not found at ${STATE_FILE}; run create first or set STATE_FILE"
  fi

  # shellcheck disable=SC1090
  source "${STATE_FILE}"
}

resolve_region() {
  if [[ -z "${AWS_REGION}" ]]; then
    AWS_REGION="$(aws configure get region 2>/dev/null || true)"
  fi

  if [[ -z "${AWS_REGION}" ]]; then
    die "AWS region not set; pass --region or configure a default AWS CLI region"
  fi
}

ensure_name_prefix() {
  local name="$1"
  if [[ "${name}" == "${NAME_PREFIX}"* ]]; then
    printf '%s\n' "${name}"
  else
    printf '%s%s\n' "${NAME_PREFIX}" "${name}"
  fi
}

wait_for_nat_deletion() {
  local nat_id="$1"
  local attempts=40

  while (( attempts > 0 )); do
    local state
    state="$(aws_cli ec2 describe-nat-gateways --nat-gateway-ids "${nat_id}" --query 'NatGateways[0].State' --output text 2>/dev/null || true)"
    if [[ "${state}" == "deleted" ]] || [[ "${state}" == "None" ]] || [[ -z "${state}" ]]; then
      return 0
    fi
    sleep 15
    attempts=$((attempts - 1))
  done

  die "timed out waiting for NAT gateway ${nat_id} to delete"
}

wait_for_addon_deletion() {
  local cluster_name="$1"
  local addon_name="$2"
  local attempts=40

  while (( attempts > 0 )); do
    if ! aws_cli eks describe-addon --cluster-name "${cluster_name}" --addon-name "${addon_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 15
    attempts=$((attempts - 1))
  done

  die "timed out waiting for addon ${addon_name} to delete"
}

resource_exists() {
  "$@" >/dev/null 2>&1
}

delete_or_warn() {
  local label="$1"
  shift

  if ! "$@" >/dev/null 2>&1; then
    log "WARNING: failed to delete ${label}"
    return 1
  fi
}

wait_for_vpc_deletion() {
  local vpc_id="$1"
  local attempts=20

  while (( attempts > 0 )); do
    if ! aws_cli ec2 describe-vpcs --vpc-ids "${vpc_id}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 15
    attempts=$((attempts - 1))
  done

  log "WARNING: VPC ${vpc_id} still exists after delete attempt"
  return 1
}

wait_until_cluster_exists() {
  local cluster_name="$1"
  local attempts=20

  while (( attempts > 0 )); do
    if aws_cli eks describe-cluster --name "${cluster_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 15
    attempts=$((attempts - 1))
  done

  die "cluster ${cluster_name} was not discoverable after creation"
}

wait_until_nodegroup_exists() {
  local cluster_name="$1"
  local nodegroup_name="$2"
  local attempts=20

  while (( attempts > 0 )); do
    if aws_cli eks describe-nodegroup --cluster-name "${cluster_name}" --nodegroup-name "${nodegroup_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 15
    attempts=$((attempts - 1))
  done

  die "node group ${nodegroup_name} was not discoverable after creation"
}

wait_until_addon_exists() {
  local cluster_name="$1"
  local addon_name="$2"
  local attempts=20

  while (( attempts > 0 )); do
    if aws_cli eks describe-addon --cluster-name "${cluster_name}" --addon-name "${addon_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 15
    attempts=$((attempts - 1))
  done

  die "addon ${addon_name} was not discoverable after creation"
}

check_vpc_quota_headroom() {
  local vpc_count
  vpc_count="$(
    aws_cli ec2 describe-vpcs \
      --query 'length(Vpcs)' \
      --output text
  )"

  # Most AWS accounts default to 5 VPCs per region.
  # We use that as a conservative preflight check so the failure mode is clearer.
  if [[ "${vpc_count}" =~ ^[0-9]+$ ]] && (( vpc_count >= 5 )); then
    die "AWS region ${AWS_REGION} already has ${vpc_count} VPCs. This usually means you have hit the default VPC quota for the region. Delete an unused VPC, run the smoke test in another region, or request a VPC quota increase, then rerun the script."
  fi
}

role_exists() {
  aws iam get-role --role-name "$1" >/dev/null 2>&1
}

cluster_exists() {
  aws_cli eks describe-cluster --name "$1" >/dev/null 2>&1
}

nodegroup_exists() {
  aws_cli eks describe-nodegroup --cluster-name "$1" --nodegroup-name "$2" >/dev/null 2>&1
}

addon_exists() {
  aws_cli eks describe-addon --cluster-name "$1" --addon-name "$2" >/dev/null 2>&1
}

create_role() {
  local role_name="$1"
  local trust_policy_file="$2"

  aws iam create-role \
    --role-name "${role_name}" \
    --assume-role-policy-document "file://${trust_policy_file}" \
    --tags "Key=Name,Value=${role_name}" "Key=Project,Value=${PROJECT_TAG}" "Key=Environment,Value=smoke" "Key=ManagedBy,Value=aws-cli" \
    --query 'Role.Arn' \
    --output text
}

delete_role_and_policies() {
  local role_name="$1"

  if ! role_exists "${role_name}"; then
    return 0
  fi

  local attached
  attached="$(aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text)"

  if [[ -n "${attached}" && "${attached}" != "None" ]]; then
    for policy_arn in ${attached}; do
      aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}"
    done
  fi

  aws iam delete-role --role-name "${role_name}"
}

build_names() {
  TEST_NAME="$(ensure_name_prefix "${TEST_NAME}")"
  EKS_CLUSTER_NAME="${TEST_NAME}-eks"
  NODEGROUP_NAME="${TEST_NAME}-ng"
  CLUSTER_ROLE_NAME="${TEST_NAME}-eks-cluster-role"
  NODE_ROLE_NAME="${TEST_NAME}-eks-node-role"
  EBS_CSI_ROLE_NAME="${TEST_NAME}-ebs-csi-role"
  LOG_GROUP_NAME="/aws/eks/${EKS_CLUSTER_NAME}/cluster"
}

create_smoke_test() {
  require_cmd aws
  require_cmd openssl
  require_cmd awk
  require_cmd cut
  require_cmd tr

  resolve_region
  build_names

  log "Running script version ${SCRIPT_VERSION}"

  if [[ -f "${STATE_FILE}" ]]; then
    die "state file already exists at ${STATE_FILE}; destroy first or move the file aside"
  fi

  log "Verifying AWS identity"
  aws sts get-caller-identity >/dev/null

  log "Checking VPC quota headroom in ${AWS_REGION}"
  check_vpc_quota_headroom

  log "Selecting two availability zones in ${AWS_REGION}"
  read -r AZ_1 AZ_2 < <(
    aws_cli ec2 describe-availability-zones \
      --filters Name=state,Values=available \
      --query 'AvailabilityZones[0:2].ZoneName' \
      --output text
  )

  if [[ -z "${AZ_1}" || -z "${AZ_2}" ]]; then
    die "unable to resolve two available availability zones in ${AWS_REGION}"
  fi

  write_state

  log "Creating VPC"
  VPC_ID="$(
    aws_cli ec2 create-vpc \
      --cidr-block "${VPC_CIDR}" \
      --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${TEST_NAME}-vpc},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'Vpc.VpcId' \
      --output text
  )"
  write_state

  aws_cli ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-support '{"Value":true}'
  aws_cli ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames '{"Value":true}'

  log "Creating internet gateway"
  INTERNET_GATEWAY_ID="$(
    aws_cli ec2 create-internet-gateway \
      --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${TEST_NAME}-igw},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'InternetGateway.InternetGatewayId' \
      --output text
  )"
  write_state
  aws_cli ec2 attach-internet-gateway --internet-gateway-id "${INTERNET_GATEWAY_ID}" --vpc-id "${VPC_ID}"

  log "Creating public and private subnets"
  PUBLIC_SUBNET_1_ID="$(
    aws_cli ec2 create-subnet \
      --vpc-id "${VPC_ID}" \
      --availability-zone "${AZ_1}" \
      --cidr-block "${PUBLIC_SUBNET_1_CIDR}" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${TEST_NAME}-public-${AZ_1}},{Key=kubernetes.io/role/elb,Value=1},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'Subnet.SubnetId' \
      --output text
  )"
  PUBLIC_SUBNET_2_ID="$(
    aws_cli ec2 create-subnet \
      --vpc-id "${VPC_ID}" \
      --availability-zone "${AZ_2}" \
      --cidr-block "${PUBLIC_SUBNET_2_CIDR}" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${TEST_NAME}-public-${AZ_2}},{Key=kubernetes.io/role/elb,Value=1},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'Subnet.SubnetId' \
      --output text
  )"
  PRIVATE_SUBNET_1_ID="$(
    aws_cli ec2 create-subnet \
      --vpc-id "${VPC_ID}" \
      --availability-zone "${AZ_1}" \
      --cidr-block "${PRIVATE_SUBNET_1_CIDR}" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${TEST_NAME}-private-${AZ_1}},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'Subnet.SubnetId' \
      --output text
  )"
  PRIVATE_SUBNET_2_ID="$(
    aws_cli ec2 create-subnet \
      --vpc-id "${VPC_ID}" \
      --availability-zone "${AZ_2}" \
      --cidr-block "${PRIVATE_SUBNET_2_CIDR}" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${TEST_NAME}-private-${AZ_2}},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'Subnet.SubnetId' \
      --output text
  )"
  write_state

  aws_cli ec2 modify-subnet-attribute --subnet-id "${PUBLIC_SUBNET_1_ID}" --map-public-ip-on-launch
  aws_cli ec2 modify-subnet-attribute --subnet-id "${PUBLIC_SUBNET_2_ID}" --map-public-ip-on-launch

  log "Creating public routing"
  PUBLIC_ROUTE_TABLE_ID="$(
    aws_cli ec2 create-route-table \
      --vpc-id "${VPC_ID}" \
      --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${TEST_NAME}-public-rt},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'RouteTable.RouteTableId' \
      --output text
  )"
  write_state

  aws_cli ec2 create-route --route-table-id "${PUBLIC_ROUTE_TABLE_ID}" --destination-cidr-block 0.0.0.0/0 --gateway-id "${INTERNET_GATEWAY_ID}" >/dev/null
  PUBLIC_ROUTE_ASSOC_1_ID="$(
    aws_cli ec2 associate-route-table \
      --route-table-id "${PUBLIC_ROUTE_TABLE_ID}" \
      --subnet-id "${PUBLIC_SUBNET_1_ID}" \
      --query 'AssociationId' \
      --output text
  )"
  PUBLIC_ROUTE_ASSOC_2_ID="$(
    aws_cli ec2 associate-route-table \
      --route-table-id "${PUBLIC_ROUTE_TABLE_ID}" \
      --subnet-id "${PUBLIC_SUBNET_2_ID}" \
      --query 'AssociationId' \
      --output text
  )"
  write_state

  log "Creating elastic IP and NAT gateway"
  ELASTIC_IP_ALLOCATION_ID="$(
    aws_cli ec2 allocate-address \
      --domain vpc \
      --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${TEST_NAME}-nat-eip},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'AllocationId' \
      --output text
  )"
  write_state

  NAT_GATEWAY_ID="$(
    aws_cli ec2 create-nat-gateway \
      --subnet-id "${PUBLIC_SUBNET_1_ID}" \
      --allocation-id "${ELASTIC_IP_ALLOCATION_ID}" \
      --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${TEST_NAME}-nat},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'NatGateway.NatGatewayId' \
      --output text
  )"
  write_state
  aws_cli ec2 wait nat-gateway-available --nat-gateway-ids "${NAT_GATEWAY_ID}"

  log "Creating private routing"
  PRIVATE_ROUTE_TABLE_ID="$(
    aws_cli ec2 create-route-table \
      --vpc-id "${VPC_ID}" \
      --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${TEST_NAME}-private-rt},{Key=Project,Value=${PROJECT_TAG}},{Key=Environment,Value=smoke},{Key=ManagedBy,Value=aws-cli}]" \
      --query 'RouteTable.RouteTableId' \
      --output text
  )"
  write_state

  aws_cli ec2 create-route --route-table-id "${PRIVATE_ROUTE_TABLE_ID}" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "${NAT_GATEWAY_ID}" >/dev/null
  PRIVATE_ROUTE_ASSOC_1_ID="$(
    aws_cli ec2 associate-route-table \
      --route-table-id "${PRIVATE_ROUTE_TABLE_ID}" \
      --subnet-id "${PRIVATE_SUBNET_1_ID}" \
      --query 'AssociationId' \
      --output text
  )"
  PRIVATE_ROUTE_ASSOC_2_ID="$(
    aws_cli ec2 associate-route-table \
      --route-table-id "${PRIVATE_ROUTE_TABLE_ID}" \
      --subnet-id "${PRIVATE_SUBNET_2_ID}" \
      --query 'AssociationId' \
      --output text
  )"
  write_state

  TMP_DIR="$(mktemp -d)"
  trap cleanup_tmp_dir EXIT

  if [[ -n "${PROVIDED_CLUSTER_ROLE_ARN}" ]]; then
    log "Using pre-created EKS control plane IAM role"
    CLUSTER_ROLE_ARN="${PROVIDED_CLUSTER_ROLE_ARN}"
    CLUSTER_ROLE_NAME="${CLUSTER_ROLE_ARN##*/}"
    write_state
  else
    log "Creating IAM role for the EKS control plane"
    cat >"${TMP_DIR}/cluster-trust.json" <<'EOF'
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
    CLUSTER_ROLE_ARN="$(create_role "${CLUSTER_ROLE_NAME}" "${TMP_DIR}/cluster-trust.json")"
    write_state
    aws iam attach-role-policy --role-name "${CLUSTER_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
  fi

  if [[ -n "${PROVIDED_NODE_ROLE_ARN}" ]]; then
    log "Using pre-created managed node group IAM role"
    NODE_ROLE_ARN="${PROVIDED_NODE_ROLE_ARN}"
    NODE_ROLE_NAME="${NODE_ROLE_ARN##*/}"
    write_state
  else
    log "Creating IAM role for the managed node group"
    cat >"${TMP_DIR}/node-trust.json" <<'EOF'
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
    NODE_ROLE_ARN="$(create_role "${NODE_ROLE_NAME}" "${TMP_DIR}/node-trust.json")"
    write_state
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
  fi

  log "Creating EKS cluster ${EKS_CLUSTER_NAME}"
  cat >"${TMP_DIR}/logging.json" <<'EOF'
{
  "clusterLogging": [
    {
      "types": [
        "api",
        "audit",
        "authenticator",
        "controllerManager",
        "scheduler"
      ],
      "enabled": true
    }
  ]
}
EOF
  local create_cluster_output
  create_cluster_output="$(
    aws_cli eks create-cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --version "${CLUSTER_VERSION}" \
    --role-arn "${CLUSTER_ROLE_ARN}" \
    --resources-vpc-config "subnetIds=${PRIVATE_SUBNET_1_ID},${PRIVATE_SUBNET_2_ID},endpointPublicAccess=true,endpointPrivateAccess=true" \
    --logging "file://${TMP_DIR}/logging.json" \
    --tags "Name=${EKS_CLUSTER_NAME},Project=${PROJECT_TAG},Environment=smoke,ManagedBy=aws-cli" \
  )"
  log "create-cluster response received"
  printf '%s\n' "${create_cluster_output}"
  wait_until_cluster_exists "${EKS_CLUSTER_NAME}"
  aws_cli eks wait cluster-active --name "${EKS_CLUSTER_NAME}"

  log "Creating the smallest practical managed node group"
  aws_cli eks create-nodegroup \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP_NAME}" \
    --subnets "${PRIVATE_SUBNET_1_ID}" "${PRIVATE_SUBNET_2_ID}" \
    --node-role "${NODE_ROLE_ARN}" \
    --ami-type AL2023_x86_64_STANDARD \
    --instance-types "${NODE_INSTANCE_TYPE}" \
    --disk-size "${NODE_DISK_SIZE}" \
    --scaling-config minSize=1,maxSize=1,desiredSize=1 \
    --tags "Name=${NODEGROUP_NAME},Project=${PROJECT_TAG},Environment=smoke,ManagedBy=aws-cli" \
    >/dev/null
  wait_until_nodegroup_exists "${EKS_CLUSTER_NAME}" "${NODEGROUP_NAME}"
  aws_cli eks wait nodegroup-active --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP_NAME}"

  log "Creating OIDC provider for IRSA"
  OIDC_ISSUER="$(
    aws_cli eks describe-cluster \
      --name "${EKS_CLUSTER_NAME}" \
      --query 'cluster.identity.oidc.issuer' \
      --output text
  )"
  OIDC_PROVIDER_HOST="${OIDC_ISSUER#https://}"
  write_state

  local oidc_thumbprint
  oidc_thumbprint="$(
    echo | openssl s_client -servername "${OIDC_PROVIDER_HOST}" -showcerts -connect "${OIDC_PROVIDER_HOST}:443" 2>/dev/null \
      | awk '
          /BEGIN CERTIFICATE/ {cert=""}
          {cert=cert $0 ORS}
          /END CERTIFICATE/ {last_cert=cert}
          END {printf "%s", last_cert}
        ' \
      | openssl x509 -fingerprint -sha1 -noout \
      | cut -d= -f2 \
      | tr -d ':' \
      | tr 'A-F' 'a-f'
  )"

  OIDC_PROVIDER_ARN="$(
    aws iam create-open-id-connect-provider \
      --url "${OIDC_ISSUER}" \
      --client-id-list sts.amazonaws.com \
      --thumbprint-list "${oidc_thumbprint}" \
      --tags "Key=Name,Value=${TEST_NAME}-oidc" "Key=Project,Value=${PROJECT_TAG}" "Key=Environment,Value=smoke" "Key=ManagedBy,Value=aws-cli" \
      --query 'OpenIDConnectProviderArn' \
      --output text
  )"
  write_state

  log "Creating IAM role for the EBS CSI addon"
  cat >"${TMP_DIR}/ebs-csi-trust.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_HOST}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER_HOST}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF
  EBS_CSI_ROLE_ARN="$(create_role "${EBS_CSI_ROLE_NAME}" "${TMP_DIR}/ebs-csi-trust.json")"
  write_state
  aws iam attach-role-policy --role-name "${EBS_CSI_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

  log "Creating the aws-ebs-csi-driver addon"
  aws_cli eks create-addon \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "${EBS_CSI_ROLE_ARN}" \
    --resolve-conflicts OVERWRITE \
    --tags "Name=${TEST_NAME}-ebs-csi,Project=${PROJECT_TAG},Environment=smoke,ManagedBy=aws-cli" \
    >/dev/null
  wait_until_addon_exists "${EKS_CLUSTER_NAME}" "aws-ebs-csi-driver"
  aws_cli eks wait addon-active --cluster-name "${EKS_CLUSTER_NAME}" --addon-name aws-ebs-csi-driver

  trap - EXIT
  cleanup_tmp_dir
  TMP_DIR=""

  log "Smoke test environment is ready"
  log "State file: ${STATE_FILE}"
  log "Cluster name: ${EKS_CLUSTER_NAME}"
  log "To clean up: ${BASH_SOURCE[0]} destroy --region ${AWS_REGION}"
}

destroy_smoke_test() {
  require_cmd aws
  load_state
  resolve_region

  log "Destroying smoke test resources from ${STATE_FILE}"

  if [[ -n "${EKS_CLUSTER_NAME}" && -n "${NODEGROUP_NAME}" ]] && nodegroup_exists "${EKS_CLUSTER_NAME}" "${NODEGROUP_NAME}"; then
    log "Deleting managed node group ${NODEGROUP_NAME}"
    aws_cli eks delete-nodegroup --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP_NAME}" >/dev/null
    aws_cli eks wait nodegroup-deleted --cluster-name "${EKS_CLUSTER_NAME}" --nodegroup-name "${NODEGROUP_NAME}"
  fi

  if [[ -n "${EKS_CLUSTER_NAME}" ]] && addon_exists "${EKS_CLUSTER_NAME}" "aws-ebs-csi-driver"; then
    log "Deleting EBS CSI addon"
    aws_cli eks delete-addon --cluster-name "${EKS_CLUSTER_NAME}" --addon-name aws-ebs-csi-driver >/dev/null
    wait_for_addon_deletion "${EKS_CLUSTER_NAME}" "aws-ebs-csi-driver"
  fi

  if [[ -n "${EKS_CLUSTER_NAME}" ]] && cluster_exists "${EKS_CLUSTER_NAME}"; then
    log "Deleting EKS cluster ${EKS_CLUSTER_NAME}"
    aws_cli eks delete-cluster --name "${EKS_CLUSTER_NAME}" >/dev/null
    aws_cli eks wait cluster-deleted --name "${EKS_CLUSTER_NAME}"
  fi

  if [[ -n "${LOG_GROUP_NAME}" ]]; then
    delete_or_warn "log group ${LOG_GROUP_NAME}" aws logs delete-log-group --region "${AWS_REGION}" --log-group-name "${LOG_GROUP_NAME}" || true
  fi

  if [[ -n "${EBS_CSI_ROLE_NAME}" ]]; then
    log "Deleting IAM role ${EBS_CSI_ROLE_NAME}"
    delete_role_and_policies "${EBS_CSI_ROLE_NAME}" || log "WARNING: failed to delete IAM role ${EBS_CSI_ROLE_NAME}"
  fi

  if [[ -n "${OIDC_PROVIDER_ARN}" ]]; then
    log "Deleting OIDC provider"
    delete_or_warn "OIDC provider ${OIDC_PROVIDER_ARN}" aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_PROVIDER_ARN}" || true
  fi

  if [[ -n "${NODE_ROLE_NAME}" && -z "${PROVIDED_NODE_ROLE_ARN}" ]]; then
    log "Deleting IAM role ${NODE_ROLE_NAME}"
    delete_role_and_policies "${NODE_ROLE_NAME}" || log "WARNING: failed to delete IAM role ${NODE_ROLE_NAME}"
  fi

  if [[ -n "${CLUSTER_ROLE_NAME}" && -z "${PROVIDED_CLUSTER_ROLE_ARN}" ]]; then
    log "Deleting IAM role ${CLUSTER_ROLE_NAME}"
    delete_role_and_policies "${CLUSTER_ROLE_NAME}" || log "WARNING: failed to delete IAM role ${CLUSTER_ROLE_NAME}"
  fi

  if [[ -n "${NAT_GATEWAY_ID}" ]]; then
    log "Deleting NAT gateway ${NAT_GATEWAY_ID}"
    delete_or_warn "NAT gateway ${NAT_GATEWAY_ID}" aws_cli ec2 delete-nat-gateway --nat-gateway-id "${NAT_GATEWAY_ID}" || true
    wait_for_nat_deletion "${NAT_GATEWAY_ID}" || log "WARNING: NAT gateway ${NAT_GATEWAY_ID} may still exist"
  fi

  if [[ -n "${ELASTIC_IP_ALLOCATION_ID}" ]]; then
    log "Releasing elastic IP"
    delete_or_warn "elastic IP ${ELASTIC_IP_ALLOCATION_ID}" aws_cli ec2 release-address --allocation-id "${ELASTIC_IP_ALLOCATION_ID}" || true
  fi

  if [[ -n "${PUBLIC_ROUTE_ASSOC_1_ID}" ]]; then
    delete_or_warn "route table association ${PUBLIC_ROUTE_ASSOC_1_ID}" aws_cli ec2 disassociate-route-table --association-id "${PUBLIC_ROUTE_ASSOC_1_ID}" || true
  fi

  if [[ -n "${PUBLIC_ROUTE_ASSOC_2_ID}" ]]; then
    delete_or_warn "route table association ${PUBLIC_ROUTE_ASSOC_2_ID}" aws_cli ec2 disassociate-route-table --association-id "${PUBLIC_ROUTE_ASSOC_2_ID}" || true
  fi

  if [[ -n "${PRIVATE_ROUTE_ASSOC_1_ID}" ]]; then
    delete_or_warn "route table association ${PRIVATE_ROUTE_ASSOC_1_ID}" aws_cli ec2 disassociate-route-table --association-id "${PRIVATE_ROUTE_ASSOC_1_ID}" || true
  fi

  if [[ -n "${PRIVATE_ROUTE_ASSOC_2_ID}" ]]; then
    delete_or_warn "route table association ${PRIVATE_ROUTE_ASSOC_2_ID}" aws_cli ec2 disassociate-route-table --association-id "${PRIVATE_ROUTE_ASSOC_2_ID}" || true
  fi

  if [[ -n "${INTERNET_GATEWAY_ID}" && -n "${VPC_ID}" ]]; then
    delete_or_warn "internet gateway detach ${INTERNET_GATEWAY_ID}" aws_cli ec2 detach-internet-gateway --internet-gateway-id "${INTERNET_GATEWAY_ID}" --vpc-id "${VPC_ID}" || true
    delete_or_warn "internet gateway ${INTERNET_GATEWAY_ID}" aws_cli ec2 delete-internet-gateway --internet-gateway-id "${INTERNET_GATEWAY_ID}" || true
  fi

  if [[ -n "${PUBLIC_SUBNET_1_ID}" ]]; then
    delete_or_warn "subnet ${PUBLIC_SUBNET_1_ID}" aws_cli ec2 delete-subnet --subnet-id "${PUBLIC_SUBNET_1_ID}" || true
  fi

  if [[ -n "${PUBLIC_SUBNET_2_ID}" ]]; then
    delete_or_warn "subnet ${PUBLIC_SUBNET_2_ID}" aws_cli ec2 delete-subnet --subnet-id "${PUBLIC_SUBNET_2_ID}" || true
  fi

  if [[ -n "${PRIVATE_SUBNET_1_ID}" ]]; then
    delete_or_warn "subnet ${PRIVATE_SUBNET_1_ID}" aws_cli ec2 delete-subnet --subnet-id "${PRIVATE_SUBNET_1_ID}" || true
  fi

  if [[ -n "${PRIVATE_SUBNET_2_ID}" ]]; then
    delete_or_warn "subnet ${PRIVATE_SUBNET_2_ID}" aws_cli ec2 delete-subnet --subnet-id "${PRIVATE_SUBNET_2_ID}" || true
  fi

  if [[ -n "${PUBLIC_ROUTE_TABLE_ID}" ]]; then
    delete_or_warn "route table ${PUBLIC_ROUTE_TABLE_ID}" aws_cli ec2 delete-route-table --route-table-id "${PUBLIC_ROUTE_TABLE_ID}" || true
  fi

  if [[ -n "${PRIVATE_ROUTE_TABLE_ID}" ]]; then
    delete_or_warn "route table ${PRIVATE_ROUTE_TABLE_ID}" aws_cli ec2 delete-route-table --route-table-id "${PRIVATE_ROUTE_TABLE_ID}" || true
  fi

  if [[ -n "${VPC_ID}" ]]; then
    delete_or_warn "VPC ${VPC_ID}" aws_cli ec2 delete-vpc --vpc-id "${VPC_ID}" || true
    wait_for_vpc_deletion "${VPC_ID}" || true
  fi

  rm -f "${STATE_FILE}"
  log "Smoke test resources removed"
}

status_smoke_test() {
  load_state
  resolve_region

  log "State file: ${STATE_FILE}"
  log "Region: ${AWS_REGION}"
  log "Cluster: ${EKS_CLUSTER_NAME:-not-set}"

  if [[ -n "${EKS_CLUSTER_NAME}" ]] && cluster_exists "${EKS_CLUSTER_NAME}"; then
    aws_cli eks describe-cluster \
      --name "${EKS_CLUSTER_NAME}" \
      --query 'cluster.{status:status,version:version,endpoint:endpoint}' \
      --output table
  else
    log "Cluster not found"
  fi

  if [[ -n "${EKS_CLUSTER_NAME}" && -n "${NODEGROUP_NAME}" ]] && nodegroup_exists "${EKS_CLUSTER_NAME}" "${NODEGROUP_NAME}"; then
    aws_cli eks describe-nodegroup \
      --cluster-name "${EKS_CLUSTER_NAME}" \
      --nodegroup-name "${NODEGROUP_NAME}" \
      --query 'nodegroup.{status:status,instanceTypes:instanceTypes,desired:scalingConfig.desiredSize}' \
      --output table
  else
    log "Node group not found"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    create|status|destroy)
      ACTION="$1"
      ;;
    --region)
      shift
      AWS_REGION="${1:-}"
      ;;
    --name)
      shift
      TEST_NAME="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

case "${ACTION}" in
  create)
    create_smoke_test
    ;;
  status)
    status_smoke_test
    ;;
  destroy)
    destroy_smoke_test
    ;;
esac
