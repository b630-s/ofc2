# Deployment Order

## Goal

The deployment flow should build the prototype from the bottom up so that shared services exist before workloads depend on them.

## Working Order

1. Provision infrastructure.
   Script: `infra/aws-proto/deploy-infra.sh`
   For the AWS prototype, the AWS-specific deploy script first checks or creates the shared IAM roles and the lakehouse S3 bucket, then Terraform creates the VPC, subnets, EKS cluster, managed node groups, EBS CSI add-on wiring, and S3 gateway endpoint.

2. Connect kubectl to the cluster.
   Script: `platform/scripts/02-connect-cluster.sh`
   This updates kubeconfig for the target EKS cluster so all following scripts operate on the intended cluster.

3. Install platform operators and shared services.
   Script: `platform/scripts/03-0-deploy-platform.sh`
   The script will try to resolve these from Terraform outputs automatically, but you can also export them explicitly before running it:
   - `POLARIS_S3_ROLE_ARN`
   - `SPARK_S3_ROLE_ARN`
   - `AIRFLOW_S3_ROLE_ARN`

   This includes:
   - Strimzi for Kafka
   - Spark Operator
   - Airflow
   - Polaris
   - Prometheus and Grafana monitoring
   - ingress as needed

   Flink and MinIO are intentionally not part of the current code path. They can be added back in a later phase if needed.

4. Validate the platform base.
   Script: `platform/scripts/04-validate-platform.sh`
   This validates only the current milestone: nodes, required operators, Airflow, monitoring, and Polaris.
   In the current working AWS prototype, this should pass once Strimzi, Spark Operator, Prometheus/Grafana, Airflow, and Polaris are all healthy.

5. Deploy sample workloads.
   Workload entry helpers: `reference-workloads/orders-reference/scripts/load-orders-events-to-kafka.sh` and `scripts/check-orders-events-in-kafka.sh`
   This includes:
   - Spark batch pipeline
   - Spark streaming pipeline
   - Airflow DAGs

   Flink streaming is a next-phase optional workload.

6. Clean up platform services.
   Script: `platform/scripts/06-cleanup-platform.sh`
   This removes Kubernetes services and Helm releases only. It does not destroy AWS infrastructure.

7. Destroy infrastructure when you want to stop AWS charges.
   Script: `infra/aws-proto/destroy-infra.sh`
   This runs Terraform destroy for the AWS prototype environment. Shared IAM roles and the external lakehouse bucket are not deleted by this workflow.

## Validation Expectations

At minimum, the current platform-only validation should prove:

- cluster infrastructure is healthy
- operators are running
- Airflow scheduler is running
- Prometheus/Grafana monitoring is running
- Polaris is healthy

## Portability Reminder

The deployment order should remain conceptually the same across EKS, AKS, GKE, OpenShift, and on-prem Kubernetes. The infrastructure provisioning step may change, but the platform and workload flow should remain consistent.
