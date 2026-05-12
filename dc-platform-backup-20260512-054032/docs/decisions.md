# Decisions

## Current Decisions

This file captures the current architectural decisions that should guide implementation unless we explicitly revise them later.

### 1. Kubernetes Is the Platform Control Surface

The platform is built around upstream Kubernetes primitives and operators rather than cloud-specific orchestration services.

Reason:
- This is the most important enabler for multi-cloud and on-prem portability.

### 2. AWS Is Limited to Infra Below Kubernetes

For the AWS prototype, acceptable coupling is limited to:

- EC2
- VPC
- EBS or EFS
- S3 for the AWS prototype object store
- EKS as managed control plane

Reason:
- These differences are unavoidable infrastructure substitutions and should not leak into the platform or workload layers.

### 3. Workloads Use Kubernetes Identity, Not Cloud Identity

Application workloads should authenticate through Kubernetes-native patterns and in-cluster configuration, not AWS-specific IAM integration for normal application behavior.

Reason:
- Cloud identity assumptions break portability and increase sovereignty friction.

Note:
- Cluster infrastructure add-ons that are inherently cloud-facing may still require tightly scoped cloud integration where unavoidable.
- On EKS, IRSA is acceptable as the AWS implementation of Kubernetes service-account identity, provided application code still uses portable object-store/catalog configuration rather than direct AWS control-plane calls.

### 4. Object Storage Is a Platform Abstraction

Platform components should target object storage through a portable S3-compatible interface instead of depending on AWS-native storage APIs in application code.

Reason:
- This keeps Spark, Airflow, Polaris, Iceberg, and later Flink integrations portable across cloud and on-prem environments.

Current AWS prototype decision:
- Use Amazon S3 for the current 8-10 week AWS scope.
- Do not deploy MinIO in the current AWS scope.
- Keep object storage wiring behind portable S3-compatible configuration so MinIO, Ceph, or another S3-compatible store can be used for on-prem or later non-AWS environments.

### 5. Iceberg Is the Table Standard

Apache Iceberg is the standard table format for the prototype.

Reason:
- It supports open interoperability across engines and aligns with the long-term lakehouse direction.

### 6. Polaris Is Required For Catalog Services

The prototype should use Polaris as the required open catalog service for Iceberg integration.

Reason:
- The latest architecture direction favors an open catalog service without coupling the platform to a proprietary metastore.

### 7. OSS Engines Only in the Data Plane

The current prototype data plane is based on:

- Apache Kafka
- Apache Spark
- Apache Airflow OSS
- Polaris
- Apache Iceberg
- Prometheus and Grafana for monitoring

Flink remains part of the target architecture, but it is optional and deferred from the current committed scope.

Reason:
- The platform must remain deployable in sovereign and non-hyperscaler environments.

### 8. Workloads Must Be Portable by Default

Batch and streaming jobs should be written so they can run unchanged across EKS, AKS, GKE, OpenShift, and on-prem Kubernetes, except for environment-specific deployment inputs such as endpoints, credentials, and storage classes.

Reason:
- The prototype is intended to prove a repeatable "run anywhere" operating model, not just an AWS-hosted stack.

### 9. Monitoring Is Required In The Platform Baseline

Prometheus and Grafana are required platform services for the current prototype baseline.

Reason:
- Multi-tenant platform validation needs visibility into cluster health, operator health, and workload execution.
- Monitoring should be available before workload demonstrations so failures can be diagnosed consistently.

## Open Follow-Ups

The following areas still need concrete implementation choices in the repo:

- external metadata database strategy for Airflow
- production hardening for Polaris runtime configuration, authentication, and catalog bootstrap
- shared secret and configuration patterns for S3, Kafka, and catalog access
- CI/CD pipeline shape for repeatable validation across environments
