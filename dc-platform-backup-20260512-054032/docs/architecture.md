# Architecture

## Purpose

DCX is being prototyped as a portable, sovereign-ready lakehouse platform that can run across public cloud and on-prem Kubernetes environments without redesigning the data platform layer for each provider.

The immediate workspace focus is an AWS prototype on EKS, but the architecture must remain valid for AKS, GKE, OpenShift, and on-prem Kubernetes.

## Platform Model

The platform is organized into four layers:

1. Infrastructure layer
   Provides compute, networking, and persistent storage primitives for Kubernetes.
2. Kubernetes platform layer
   Provides namespaces, service accounts, operators, ingress, Prometheus/Grafana monitoring, and shared runtime services.
3. Data platform layer
   Provides Kafka, Spark, Airflow, Polaris, Iceberg, and object storage integration. Flink remains a next-phase optional streaming engine.
4. Workload layer
   Provides batch and streaming pipelines, orchestration DAGs, and reusable processing patterns.

## Target Components

The current target stack is:

- Apache Kafka for event ingestion
- Apache Spark for batch and streaming workloads
- Apache Airflow OSS for orchestration
- Prometheus and Grafana for platform and workload monitoring
- Polaris for required catalog services
- Apache Iceberg for table format
- Amazon S3 for the current AWS prototype object store
- Apache Flink for streaming workloads in a later optional phase

## Portability Principles

The architecture must follow these rules:

- Use Kubernetes as the control surface for workloads.
- Use Kubernetes-native service accounts and upstream Kubernetes APIs.
- Treat object storage as a generic interface rather than coupling to a specific cloud data service.
- Use S3 for the current AWS prototype while keeping storage access behind object-store and catalog configuration boundaries.
- Keep runtime configuration portable across clouds.
- Avoid cloud-specific SDKs and identity assumptions inside workloads.
- Prefer CNCF and Apache components over cloud-managed proprietary services in the data plane.

## AWS Boundary

AWS is acceptable only at the infrastructure boundary of the prototype:

- EC2 for worker compute
- VPC for networking
- EBS or EFS for persistent node-attached or file-backed storage
- S3 for the current prototype object store, exposed to workloads as an S3-compatible storage interface
- EKS for managed Kubernetes control plane operations

The platform above Kubernetes should not need to know whether it is running on AWS, Azure, GCP, OpenShift, or bare metal.

## Initial Deployment Shape

The current repository structure reflects the following deployment model:

- Terraform provisions AWS network, EKS, S3 lakehouse storage, private S3 routing, and scoped workload IAM roles for the prototype environment.
- Kubernetes manifests and Helm values configure namespaces, service accounts, operators, and shared platform services.
- Workloads and shared services are deployed into dedicated namespaces for `kafka`, `spark`, `airflow`, `polaris`, `monitoring`, and platform operators. Flink remains a deferred optional next phase, and a `flink` namespace is not part of the current repository shape. `minio` is not part of the current AWS scope.
- Sample data pipelines will demonstrate Kafka or file ingestion, Spark processing, and writes into S3-backed Iceberg tables through Polaris.

## Design Outcome

If successful, this prototype should show that DCX can be packaged as a "run anywhere" platform:

- same architecture
- same core services
- same workload model
- only infrastructure adapters changing per environment
