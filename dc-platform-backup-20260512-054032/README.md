# DCX Run Anywhere Prototype

This repository contains the in-progress prototype for a sovereign-ready, portable data platform that can run across managed cloud Kubernetes and on-prem Kubernetes with minimal or no workload changes.

The current prototype direction is:

- Kubernetes as the runtime layer
- Apache Kafka for event ingress
- Apache Spark for batch and streaming workloads
- Apache Airflow OSS for orchestration
- Apache Iceberg for table format
- Polaris as the required open catalog
- Prometheus and Grafana for monitoring
- Amazon S3 for the current AWS prototype object store
- Apache Flink as an optional next-phase streaming engine

The AWS prototype is only one deployment target. The platform itself is intended to remain portable across:

- AWS EKS
- Azure AKS
- GKE
- OpenShift
- on-prem Kubernetes

## Core Rules

These are the current architectural guardrails for all code in this repo.

- EKS is used only as a managed Kubernetes control plane.
- Workloads authenticate through Kubernetes-native identity, not cloud identity.
- Platform services and data engines must target object storage generically, not AWS-specific data services.
- Applications must not rely on AWS SDKs, AWS auth flows, or AWS control-plane APIs for normal runtime behavior.
- The platform layer must use upstream Kubernetes APIs plus CNCF and Apache projects wherever possible.
- Spark, Airflow, Kafka, Polaris, Iceberg, monitoring, and later Flink integrations should be designed to run unchanged across cloud and on-prem environments.

## Acceptable Cloud Coupling

The only unavoidable cloud coupling should sit below Kubernetes:

- compute infrastructure such as EC2, Azure VMs, or GCE
- network substrate such as VPC or equivalent
- node-attached block or file storage such as EBS, EFS, or equivalents
- object storage endpoints and buckets, provided through a portable S3-compatible interface

These infrastructure differences are acceptable because the platform should not need to change when they are replaced.

## Prototype Goals

The prototype is intended to demonstrate:

- cloud-agnostic deployment capability
- sovereign-ready architecture
- end-to-end ingestion, transformation, and publishing workflows
- reusable batch and streaming patterns
- repeatable deployment using Terraform, Helm, and automation scripts

## Current Status

The repository is an active work in progress. The infrastructure and platform layout are being scaffolded first, followed by deployable platform components, sample workloads, and validation flows.

See [docs/architecture.md](/c:/Users/baljeet/Documents/projects/dc-platform/docs/architecture.md), [docs/decisions.md](/c:/Users/baljeet/Documents/projects/dc-platform/docs/decisions.md), and [docs/deployment-order.md](/c:/Users/baljeet/Documents/projects/dc-platform/docs/deployment-order.md) for the current working design.

Operator runbooks:

- AWS infra: [infra/aws-proto/README.md](/c:/Users/baljeet/Documents/projects/dc-platform/infra/aws-proto/README.md)
- Platform lifecycle: [platform/scripts/README.md](/c:/Users/baljeet/Documents/projects/dc-platform/platform/scripts/README.md)
