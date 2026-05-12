output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "private_route_table_ids" {
  value = module.vpc.private_route_table_ids
}

output "s3_gateway_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "lakehouse_bucket_name" {
  value = data.aws_s3_bucket.lakehouse.bucket
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "ebs_csi_role_arn" {
  value = data.aws_iam_role.ebs_csi.arn
}

output "polaris_s3_role_arn" {
  value = data.aws_iam_role.lakehouse_workload["polaris"].arn
}

output "spark_s3_role_arn" {
  value = data.aws_iam_role.lakehouse_workload["spark"].arn
}

output "airflow_s3_role_arn" {
  value = data.aws_iam_role.lakehouse_workload["airflow"].arn
}

output "lakehouse_workload_role_arns" {
  value = {
    for name in keys(local.lakehouse_workload_roles) :
    name => data.aws_iam_role.lakehouse_workload[name].arn
  }
}
