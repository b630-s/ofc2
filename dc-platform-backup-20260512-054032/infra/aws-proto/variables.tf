variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
}

variable "node_instance_types" {
  description = "Managed workload node group instance types"
  type        = list(string)
}

variable "node_desired_size" {
  description = "Desired workload node count"
  type        = number
}

variable "node_min_size" {
  description = "Minimum workload node count"
  type        = number
}

variable "node_max_size" {
  description = "Maximum workload node count"
  type        = number
}

variable "node_disk_size" {
  description = "Disk size in GiB for workload worker nodes"
  type        = number
}

variable "core_node_instance_types" {
  description = "Managed core node group instance types"
  type        = list(string)
}

variable "core_node_desired_size" {
  description = "Desired core node count"
  type        = number
}

variable "core_node_min_size" {
  description = "Minimum core node count"
  type        = number
}

variable "core_node_max_size" {
  description = "Maximum core node count"
  type        = number
}

variable "core_node_disk_size" {
  description = "Disk size in GiB for core worker nodes"
  type        = number
}

variable "eks_cluster_role_name" {
  description = "IAM role name for the EKS control plane role"
  type        = string
}

variable "eks_node_role_name" {
  description = "IAM role name for the EKS managed node group role"
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "S3 bucket name for the prototype lakehouse"
  type        = string
}

variable "ebs_csi_role_name" {
  description = "IAM role name for the EBS CSI driver IRSA role"
  type        = string
}

variable "polaris_s3_role_name" {
  description = "IAM role name for the Polaris S3 access role"
  type        = string
}

variable "spark_s3_role_name" {
  description = "IAM role name for the Spark S3 access role"
  type        = string
}

variable "airflow_s3_role_name" {
  description = "IAM role name for the Airflow S3 access role"
  type        = string
}
