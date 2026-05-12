locals {
  lakehouse_workload_roles = {
    airflow = {
      namespace       = "airflow"
      service_account = "airflow-sa"
      role_name       = var.airflow_s3_role_name
    }
    polaris = {
      namespace       = "polaris"
      service_account = "polaris-sa"
      role_name       = var.polaris_s3_role_name
    }
    spark = {
      namespace       = "spark"
      service_account = "spark-sa"
      role_name       = var.spark_s3_role_name
    }
  }
}

data "aws_iam_role" "lakehouse_workload" {
  for_each = local.lakehouse_workload_roles

  name = each.value.role_name
}
