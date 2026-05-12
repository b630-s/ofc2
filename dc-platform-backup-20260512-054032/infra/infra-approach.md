# Infra Approach

## Purpose

This document explains the current AWS infrastructure approach for the prototype, the intentional hard-coded decisions in the repo, and the later upgrades we expect to make in phase 2 and phase 3.

The goal is to keep the infrastructure layer:

- simple enough to operate during the current prototype window
- aligned with the platform portability rules above Kubernetes
- explicit about where we are making AWS-specific choices

## Current Folder Layout

The active AWS infrastructure code lives in:

- `infra/aws-proto/providers.tf`
- `infra/aws-proto/versions.tf`
- `infra/aws-proto/network.tf`
- `infra/aws-proto/eks.tf`
- `infra/aws-proto/storage.tf`
- `infra/aws-proto/iam.tf`
- `infra/aws-proto/variables.tf`
- `infra/aws-proto/terraform.tfvars`
- `infra/aws-proto/outputs.tf`

We intentionally flattened the earlier Terraform module structure into a single AWS-focused folder because:

- the current implementation is AWS-specific anyway
- one readable folder is easier to review and operate
- separating by file is enough for the current scope

The file split reflects real concerns:

- `network.tf`: VPC and subnet layer
- `eks.tf`: EKS cluster and node groups
- `storage.tf`: external S3 lakehouse bucket reference and private S3 routing
- `iam.tf`: workload IAM roles for S3 access

## Current AWS Infrastructure Scope

The current AWS prototype creates only the infrastructure needed to run the Kubernetes platform baseline.

### 1. Network

Current implementation:

- one VPC
- two public subnets across two AZs
- two private subnets across two AZs
- DNS support and DNS hostnames enabled
- one NAT gateway
- subnet tags for Kubernetes public and internal load balancers

Current rationale:

- this is the smallest practical EKS network shape for the prototype
- it is easy to reason about and cheap compared with more advanced multi-NAT or multi-CIDR layouts

### 2. EKS Cluster

Current implementation:

- one EKS cluster
- control plane logging enabled for:
  - `api`
  - `audit`
  - `authenticator`
  - `controllerManager`
  - `scheduler`
- IRSA enabled
- core EKS add-ons:
  - CoreDNS
  - kube-proxy
  - VPC CNI
- EBS CSI add-on

### 3. Node Groups

Current implementation:

- one dedicated core node group
- one dedicated workload node group
- both currently reuse the same admin-provided node IAM role

Current labels:

- core node group:
  - `NodeGroupType=core`
  - `WorkloadClass=platform`
- workload node group:
  - `NodeGroupType=workload`
  - `WorkloadClass=tenant`

Current rationale:

- the core node group protects cluster-critical services from noisy tenant and data workloads
- the workload node group is the default place for tenant-facing execution capacity
- we intentionally did not introduce taints yet because we want a safe first separation without accidentally blocking EKS add-ons or system pods

### 4. Storage

Current implementation:

- one external S3 lakehouse bucket, checked or created by the AWS deploy script
- bucket encryption enabled with AES256
- bucket versioning enabled
- public access blocked
- one S3 gateway endpoint attached to private route tables
- EBS CSI enabled for PVC-backed Kubernetes storage

Current rationale:

- S3 is the agreed object-store choice for the current AWS scope
- private S3 routing avoids pushing node-to-S3 traffic through the NAT gateway
- EBS CSI supports persistent volumes for services like Airflow PostgreSQL and Prometheus

### 5. IAM

Current implementation:

- shared EKS control plane role
- shared EKS node role
- shared EBS CSI IRSA role
- separate S3 roles for:
  - Polaris
  - Spark
  - Airflow

The current named IAM roles are:

- `dc-platform-bss-eks-cluster-role`
- `dc-platform-bss-eks-node-role`
- `dc-platform-bss-ebs-csi-role`
- `dc-platform-bss-polaris-s3-role`
- `dc-platform-bss-spark-s3-role`
- `dc-platform-bss-airflow-s3-role`

Current rationale:

- cluster and node roles are shared across smoke test and Terraform to reduce admin overhead
- workload S3 access is separated by service account so we can tighten scope later without redesigning the whole approach
- the AWS prototype treats the EBS CSI, Polaris, Spark, and Airflow roles as external roles that are checked and created by the deployment script if missing

## Current Hard-Coded Choices

These are intentional current defaults, not accidents.

### AWS Region And Environment

Current default values in `terraform.tfvars`:

- region: `us-east-1`
- environment: `proto`
- cluster name: `dc-platform-bss-eks-proto`

### Bucket Name

Current fixed bucket name:

- `dc-platform-bss-proto-lakehouse-7901580-us-east-1`

Reason:

- we agreed to use a stable unique suffix instead of generating the name from the AWS account ID

### IAM Role Names

Current fixed role names:

- `dc-platform-bss-eks-cluster-role`
- `dc-platform-bss-eks-node-role`
- `dc-platform-bss-ebs-csi-role`
- `dc-platform-bss-polaris-s3-role`
- `dc-platform-bss-spark-s3-role`
- `dc-platform-bss-airflow-s3-role`

Reason:

- admin can pre-create these once
- smoke test and Terraform can align to the same names

### External Role Handling

Current behavior:

- `infra/aws-proto/deploy-infra.sh` checks whether these roles already exist:
  - `dc-platform-bss-eks-cluster-role`
  - `dc-platform-bss-eks-node-role`
- `infra/aws-proto/deploy-infra.sh` checks whether these roles already exist:
  - `dc-platform-bss-ebs-csi-role`
  - `dc-platform-bss-polaris-s3-role`
  - `dc-platform-bss-spark-s3-role`
  - `dc-platform-bss-airflow-s3-role`
- `infra/aws-proto/deploy-infra.sh` checks whether the lakehouse bucket already exists:
  - `dc-platform-bss-proto-lakehouse-7901580-us-east-1`
- if a role exists, the script reuses it
- if a role does not exist, the script creates it before Terraform plan/apply
- if the bucket exists, the script reuses it
- if the bucket does not exist, the script creates it and applies the baseline bucket settings
- Terraform itself only references these roles and the bucket as existing external resources and does not own them

Reason:

- this keeps destroy from removing these roles
- this keeps destroy from removing the lakehouse bucket
- it allows admin-created roles and script-created roles to follow the same path
- it gives visible console output about what the infra script is doing

Important behavior:

- the script may create missing external roles during `--plan` or `--apply`
- the script may create the external lakehouse bucket during `--plan` or `--apply`
- during `--apply`, the script now:
  - runs `terraform fmt -recursive`
  - bootstraps the VPC and NAT path first
  - bootstraps only the EKS control plane next
  - updates IRSA trust once the cluster OIDC issuer exists
  - then runs the full Terraform apply
- after a successful `--apply`, the script writes timestamped local backups of `terraform.tfstate` into `infra/aws-proto/bkp/`
- for the cluster role it attaches `AmazonEKSClusterPolicy`
- for the node role it attaches:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEC2ContainerRegistryPullOnly`
  - `AmazonEKS_CNI_Policy`
- once the cluster OIDC issuer exists, the script updates the IRSA trust policies for EBS CSI, Polaris, Spark, and Airflow before the full Terraform apply continues

### Node Group Defaults

Current workload node group defaults:

- instance type: `t3.medium`
- desired: `2`
- min: `2`
- max: `3`
- disk: `50`

Current core node group defaults:

- instance type: `t3.medium`
- desired: `2`
- min: `2`
- max: `2`
- disk: `50`

Reason:

- two core nodes gives basic resilience for platform services across two AZs
- the current settings are still modest enough for prototype cost control

### Availability Zones

Current fixed AZs:

- `us-east-1a`
- `us-east-1b`

Reason:

- explicit inputs are simpler to reason about in the prototype
- dynamic discovery can be added later if needed

## Current Scheduling Approach

The current platform scheduling intent is:

- core platform services should run on the core node group when their chart values support direct node selection
- tenant or data workloads should use the workload node group by default

Currently pinned to core nodes:

- Spark Operator
- Strimzi operator
- Polaris
- Polaris PostgreSQL
- Airflow control-plane components
- Prometheus / Grafana control-plane components where chart values clearly support it

Not yet explicitly pinned:

- EKS-managed add-ons like CoreDNS
- workload pods created later by Spark jobs or Airflow tasks

Reason:

- we only added selectors where our current chart values clearly supported them without higher rollout risk
- Airflow and deeper workload placement need a second pass with chart-level verification

## Current Sequence Of Infrastructure Setup

The infrastructure comes up in this order:

1. AWS provider configuration
2. VPC and subnets
3. NAT and route tables
4. EKS cluster control plane
5. IRSA trust updates using the cluster OIDC issuer
6. core and workload managed node groups
7. EBS CSI role and add-on
8. S3 lakehouse bucket check or creation
9. S3 gateway endpoint
10. S3 workload IAM roles for Polaris, Spark, and Airflow
11. kubeconfig update through `platform/scripts/02-connect-cluster.sh`
12. platform install through `platform/scripts/03-0-deploy-platform.sh`

## Decisions We Intentionally Did Not Implement Yet

The current prototype does not yet include:

- Karpenter
- spot node pools
- taints on core nodes
- separate log bucket
- dynamic AZ discovery
- multi-NAT architecture
- extra VPC endpoints beyond S3
- explicit root volume IOPS or throughput tuning
- AWS Pod Identity as the baseline identity model

Reason:

- these all increase complexity
- some are more AWS-specific than our current portability baseline should absorb
- they are better treated as targeted upgrades once the baseline is stable

## Phase 2 Upgrades

The next layer of recommended hardening is:

- add explicit workload placement for Airflow components
- add explicit placement guidance for sample Spark jobs and future tenant workloads
- review whether core nodes should be tainted after validating EKS add-on behavior
- split logs and operational artifacts from the main lakehouse bucket, or at least formalize bucket prefixes
- add additional VPC endpoints if traffic/security/cost needs justify them
- replace remaining bootstrap secret-based object-store access patterns with stronger IRSA-first wiring
- add Terraform remote state backend and locking
- tighten IAM scope further by service and possibly by bucket prefix

## Phase 3 Upgrades

The later AWS optimization layer can include:

- optional Karpenter for Spark and elastic compute
- on-demand and spot node-class separation
- stronger tenant isolation using taints, tolerations, quotas, and dedicated node pools where needed
- dynamic AZ discovery
- more advanced storage tuning for workload classes
- node root volume tuning beyond size alone
- separate environment folders if we truly need multiple AWS environments
- deeper cost and resiliency tuning across node groups and storage classes

## Guiding Principle

The current AWS infrastructure should remain:

- AWS-specific below Kubernetes
- portable above Kubernetes

That means:

- VPC, EKS, EBS, S3, and IAM are allowed AWS substitutions
- Airflow, Spark, Kafka, Polaris, monitoring, and workloads should still be designed so the platform model survives a future AKS, GKE, or on-prem implementation
