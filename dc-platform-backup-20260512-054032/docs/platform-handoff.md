# Platform Handoff For Data Engineering

## Purpose

This document describes the currently available AWS prototype platform baseline and how data engineering teams should use it when starting workflow development.

The goal is to give teams a working shared platform for:

- Spark batch jobs
- Spark streaming jobs
- Airflow DAG orchestration
- Iceberg catalog access through Polaris
- S3-backed lakehouse storage

## Current Platform Status

The following base platform components are installed and validated on the EKS prototype cluster:

- EKS cluster: `dc-platform-bss-eks-proto`
- Spark Operator
- Airflow
- Strimzi operator
- Polaris
- Prometheus and Grafana

The following platform foundations are also in place:

- IRSA-based AWS access for Spark, Airflow, and Polaris
- EBS-backed persistence for platform services
- S3 lakehouse bucket
- dedicated namespaces and service accounts

## What Is Available Today

### Kubernetes Namespaces

- `platform-system`
  Used for shared platform operators such as Strimzi and Spark Operator.

- `monitoring`
  Used for Prometheus and Grafana.

- `spark`
  Target namespace for Spark workloads and SparkApplication resources.

- `airflow`
  Target namespace for Airflow components and workflow orchestration.

- `polaris`
  Target namespace for Polaris and its PostgreSQL backing store.

- `kafka`
  Reserved for Kafka resources managed through Strimzi.

## Service Accounts And Runtime Identity

These service accounts already exist and are the intended runtime identities:

- `spark/spark-sa`
- `airflow/airflow-sa`
- `polaris/polaris-sa`

These are annotated with IRSA roles so workloads can use AWS access without static access keys.

Current role mapping:

- Spark: `dc-platform-bss-spark-s3-role`
- Airflow: `dc-platform-bss-airflow-s3-role`
- Polaris: `dc-platform-bss-polaris-s3-role`

## Storage

Current S3 lakehouse bucket:

- `dc-platform-bss-proto-lakehouse-7901580-us-east-1`

This bucket is the shared object-storage location for:

- raw and curated data
- Iceberg table data
- future checkpoints and workflow artifacts



## Platform Components And Intended Use

### Spark Operator

Available for:

- batch Spark jobs
- streaming Spark jobs
- Kubernetes-native SparkApplication deployment

Expected usage pattern:

- package Spark jobs into an image or agreed runtime bundle
- deploy with SparkApplication manifests
- use `spark-sa`
- read and write S3 through IRSA
- use Polaris for Iceberg catalog access

### Airflow

Available for:

- DAG orchestration
- scheduling batch workflows
- coordinating Spark jobs

Expected usage pattern:

- DAGs should orchestrate jobs, not carry embedded infrastructure logic
- Airflow runtime should use `airflow-sa`
- Kubernetes-native job submission patterns are preferred

### Polaris

Available for:

- Iceberg catalog and metadata layer

Expected usage pattern:

- Spark workloads should use Polaris as the catalog abstraction
- data/table definitions should align with agreed namespace conventions

### Strimzi

Currently installed as the Kafka operator only.

Important:

- Kafka brokers are not yet deployed
- topics are not yet deployed
- if a workflow depends on Kafka, the next step is to deploy a Kafka cluster and topic resources

### Monitoring

Available for:

- cluster and platform health checks
- Prometheus metrics
- Grafana dashboards

This is intended for platform and workload observability, not only infra verification.

## What Is Not Yet Delivered

The following are not yet part of the baseline:

- a deployed Kafka broker cluster
- reference Kafka topics
- sample Spark batch jobs
- sample Spark streaming jobs
- production-ready Airflow DAG examples
- automated Polaris catalog bootstrap for workload teams
- a clearer workload-layer execution path under `reference-workloads/orders-reference/`

## What Data Engineers Should Build Next

Teams can now start preparing workload artifacts for:

- Spark batch pipelines
- Spark structured streaming pipelines
- Airflow DAGs
- Iceberg table definitions and namespace conventions
- data contracts and schema definitions

Recommended first reference workflow:

1. Kafka topic receives sample events
2. Spark streaming job reads events
3. Spark writes a Bronze Iceberg table through Polaris into S3
4. Spark batch job reads Bronze and writes Silver
5. Airflow orchestrates the batch step and validations

## Engineering Guidance

### Do

- use the provided Kubernetes namespaces
- use the provided service accounts
- rely on IRSA for AWS access
- assume S3-backed storage
- assume Iceberg plus Polaris for table access
- keep workflows Kubernetes-native
- keep job configuration externalized

### Do Not

- do not embed AWS access keys in code or manifests
- do not assume local disk persistence
- do not assume services are internet-exposed by default
- do not assume Kafka is already available just because Strimzi is installed

## Current Access Pattern

Most services are internal to the cluster right now.

Typical operator access is through:

- `kubectl`
- `kubectl port-forward`
- AWS Console for infra verification

If teams need broader UI access, that should be handled separately through ingress or load balancers.

## Practical Handoff To Teams

When handing this platform to workflow teams, share these facts:

- cluster name: `dc-platform-bss-eks-proto`
- region: `us-east-1`
- bucket: `dc-platform-bss-proto-lakehouse-7901580-us-east-1`
- namespaces: `spark`, `airflow`, `polaris`, `kafka`
- service accounts: `spark-sa`, `airflow-sa`, `polaris-sa`
- AWS access model: IRSA only
- current state: platform baseline ready, workload layer still to be built

## Suggested Next Delivery

The next recommended platform milestone is:

1. deploy Kafka cluster and topics
2. bootstrap Polaris catalog conventions
3. add one reference Spark batch job
4. add one reference Spark streaming job
5. add one reference Airflow DAG
6. keep the orders-reference entry scripts aligned with the actual orders-reference flow

That will turn the current baseline into a reusable end-to-end reference for the team.
