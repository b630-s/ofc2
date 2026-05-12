project_name        = "dc-platform-bss"
environment         = "proto"
aws_region          = "us-east-1"

vpc_cidr            = "10.0.0.0/16"
availability_zones  = ["us-east-1a", "us-east-1b"]

private_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]

public_subnet_cidrs = [
  "10.0.101.0/24",
  "10.0.102.0/24"
]

eks_cluster_name    = "dc-platform-bss-eks-proto"
eks_cluster_version = "1.34"

node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 3
node_disk_size      = 50

core_node_instance_types = ["t3.medium"]
core_node_desired_size   = 2
core_node_min_size       = 2
core_node_max_size       = 2
core_node_disk_size      = 50

eks_cluster_role_name = "dc-platform-bss-eks-cluster-role"
eks_node_role_name    = "dc-platform-bss-eks-node-role"

lakehouse_bucket_name = "dc-platform-bss-proto-lakehouse-790158-us-east-1"

ebs_csi_role_name   = "dc-platform-bss-ebs-csi-role"
polaris_s3_role_name = "dc-platform-bss-polaris-s3-role"
spark_s3_role_name   = "dc-platform-bss-spark-s3-role"
airflow_s3_role_name = "dc-platform-bss-airflow-s3-role"
