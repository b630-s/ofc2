# Portability Notes

## Current Prototype Choices

These notes capture deliberate short-term implementation choices for the current prototype slice.

### Airflow Metadata Database

Airflow now uses an in-cluster PostgreSQL instance managed through the Airflow Helm chart.

Why:
- It is the simplest correct deployment model for KubernetesExecutor.
- It stays portable across managed cloud Kubernetes and on-prem Kubernetes.
- It provides persistent metadata as long as the PostgreSQL volume is retained.

Tradeoff:
- This is operationally simpler than an external database, but not the final production posture.

### Airflow Logs

Airflow logs are still pod-local for now.

Why:
- The immediate goal is to make the platform base deployable first.

Follow-up:
- Wire remote logging to S3-compatible object storage later rather than cloud-specific logging services.

### Object Storage

The current AWS prototype uses Amazon S3 for object storage.

Why:
- S3 is the agreed object store for the current AWS scope.
- The AWS deploy workflow ensures the prototype lakehouse bucket exists and Terraform creates a private S3 gateway endpoint so node-to-S3 traffic does not need to traverse the NAT gateway.
- The AWS deploy workflow ensures the shared IAM roles exist, and Terraform wires them to Polaris, Spark, Airflow, and the EBS CSI add-on.
- The platform still treats object storage as a portable S3-compatible interface so the same data-plane configuration model can be adapted to MinIO, Ceph, or another S3-compatible store in later environments.

Follow-up:
- Revisit MinIO or another S3-compatible object store for on-prem and non-AWS validation in a later phase.

### Ingress And Monitoring

Monitoring is required in the deployment script for now. Ingress remains optional.

Why:
- Prometheus and Grafana are required to validate cluster health, operator health, and workload execution in a multi-tenant platform baseline.
- Ingress exposure details vary more by environment than the core data platform components.

### Helm Chart Version Pinning

The deployment script now pins Helm chart versions for reproducibility.

Why:
- Prototype validation should not drift when upstream charts publish new releases.
- Some values, especially around Strimzi and operator behavior, are version-sensitive.

Follow-up:
- Revalidate pinned versions as part of planned platform upgrades instead of absorbing chart changes implicitly.

### Polaris

Polaris now has a base installation path in the deployment script.

Why:
- The official Polaris chart expects pre-created resources, especially persistence and storage secrets.
- The chart also expects a separately managed database when using persistent storage.

Current prototype shape:
- in-cluster PostgreSQL for Polaris metadata persistence
- a Terraform-created `polaris-sa` IRSA role is wired for object-store access through IRSA
- official Polaris Helm chart installed from the Apache repository

Remaining follow-up:
- create the actual catalog through the Polaris API or CLI after install
- document the exact bootstrap flow for the S3-backed Iceberg catalog
- replace generated internal-auth defaults with managed secrets before any serious environment use

### Flink

Flink remains aligned with the long-term architecture but is not part of the committed current AWS scope.

Why:
- The current phase prioritizes EKS, S3, Polaris, Airflow, Spark, Kafka integration, and multi-tenancy baseline validation.
- Flink can be added later on top of the same Iceberg, Polaris, S3, and Kubernetes tenancy model without reworking the core platform design.
