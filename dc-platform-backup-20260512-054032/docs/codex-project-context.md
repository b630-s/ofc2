# Codex Project Context

This note summarizes the Windows Codex context imported into Ubuntu on 2026-04-30.

Raw imported sessions live under:

- `/home/ubuntu/.codex/sessions`
- original Windows source: `/mnt/c/Users/baljeet/.codex/sessions`

## Project Goal

We are building the DCX / DCP "Run Anywhere" prototype: a sovereign-ready, portable lakehouse platform that can run across managed cloud Kubernetes and on-prem Kubernetes with minimal or no workload changes.

The current prototype target is AWS EKS, but EKS is only the managed Kubernetes control plane for the first environment. The platform layer should remain portable to AKS, GKE, OpenShift, and on-prem Kubernetes.

## Current Target Stack

- Kubernetes as the runtime and control surface
- Apache Kafka for event ingress
- Apache Spark for batch and streaming workloads
- Apache Airflow OSS for orchestration
- Apache Iceberg for table format
- Apache Polaris as the required open catalog
- Prometheus and Grafana for monitoring
- Amazon S3 as the current AWS prototype object store
- Apache Flink is optional and deferred to a later phase

## Hard Architecture Rules

- EKS is used only for AWS-managed Kubernetes control plane operations.
- Workloads should use Kubernetes-native identity and upstream Kubernetes APIs.
- The platform should target object storage generically, not AWS-specific data services.
- Runtime code should avoid AWS SDKs, AWS auth flows, and AWS control-plane APIs.
- Cloud-specific coupling should stay below Kubernetes: compute, network, node storage, and object storage endpoints.
- The same platform and workload model should remain valid across EKS, AKS, GKE, OpenShift, and on-prem Kubernetes.
- Prefer CNCF and Apache components over cloud-managed proprietary data-plane services.

## Repository Shape

The repo has evolved from the initial `scripts/`, `workloads/`, and `samples/` layout into the current structure:

- `infra/aws-proto/` for AWS Terraform and infra lifecycle scripts
- `platform/` for platform manifests and Helm values
- `platform/scripts/` for platform lifecycle commands
- `reference-workloads/` for Spark, Airflow, shared smoke tests, and sample data
- `docs/` for architecture, decisions, deployment order, handoff, roadmap, and workload notes

There is no git repo yet. Treat `/home/ubuntu/work/dc-platform` as the primary WSL working copy.

## Major Work Already Done

- Captured architecture direction in `README.md`, `docs/architecture.md`, `docs/decisions.md`, and `docs/deployment-order.md`.
- Reworked AWS prototype infra into `infra/aws-proto/`.
- Added platform lifecycle scripts:
  - `platform/scripts/02-connect-cluster.sh`
  - `platform/scripts/03-0-deploy-platform.sh`
  - `platform/scripts/04-validate-platform.sh`
  - `platform/scripts/06-cleanup-platform.sh`
- Added platform values for Strimzi, Spark Operator, Airflow, Polaris, monitoring, and ingress.
- Added namespaces and service accounts for `spark`, `airflow`, `polaris`, `kafka`, `monitoring`, and platform operators.
- Added reference workload structure for Kafka, Spark batch, Spark streaming, Airflow DAGs, Polaris bootstrap, and sample data.
- Added `docs/platform-handoff.md` and `docs/two-iteration-platform-roadmap.md`.

## Live Platform State Recovered From Windows Session

The AWS prototype platform was deployed and validated on:

- cluster: `dc-platform-bss-eks-proto`
- region: `us-east-1`
- lakehouse bucket: `dc-platform-bss-proto-lakehouse-7901580-us-east-1`

Installed and validated platform components:

- Spark Operator
- Airflow
- Strimzi operator
- Polaris
- Prometheus and Grafana

Important service accounts:

- `spark/spark-sa`
- `airflow/airflow-sa`
- `polaris/polaris-sa`

The repo currently uses IRSA-backed AWS access for Spark, Airflow, and Polaris in the AWS prototype. This is acceptable as prototype infrastructure/runtime wiring, but workload logic should not become AWS-specific.

## Kafka Progress

Kafka reached a live success state.

What was proven:

- Strimzi operator reconciled successfully.
- Kafka node pools and cluster became healthy.
- Kafka topics were created.
- The reference workload layer had its first live success.

Bootstrap server:

- `reference-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092`

Topics:

- `orders_raw`
- `orders_dlq`

Important fix:

- `platform/values-strimzi-operator.yaml` must include `createGlobalResources: true`.

This was the key Strimzi fix that got Kafka reconciling correctly.

## Cleanup Bug Fixed

We hit a real lifecycle bug during cleanup:

- `kafka` namespace got stuck in `Terminating`.
- `KafkaTopic` resources still had `strimzi.io/topic-operator` finalizers.
- Strimzi had already been removed, so nothing remained to clear the finalizers.

Fix added in `platform/scripts/06-cleanup-platform.sh`:

- delete all `KafkaTopic`, `Kafka`, and `KafkaNodePool` resources before uninstalling Strimzi
- patch stuck Kafka topic finalizers best-effort
- then uninstall Strimzi and delete namespaces

## Polaris Progress

Polaris direction was updated to version:

- `1.3.0-incubating`

Files updated in Windows context and present in WSL copy:

- `platform/scripts/03-0-deploy-platform.sh`
- `platform/values-polaris.yaml`
- `reference-workloads/orders-reference/README.md`

`reference-workloads/orders-reference/README.md` now includes the prerequisite Polaris CLI install flow and the current orders-reference execution sequence:

- install Java 21, `jq`, `curl`, and `tar`
- download Polaris `1.3.0-incubating`
- create a local `polaris` wrapper
- optionally persist PATH

Next Polaris step:

- prepare Polaris admin credentials
- run `platform/scripts/03-5-bootstrap-polaris-reference.sh`
- validate catalog, namespaces, Spark principal, roles, and catalog role wiring

## Current Deployment Order

From repo root:

```bash
./infra/aws-proto/deploy-infra.sh --apply
./platform/scripts/02-connect-cluster.sh
kubectl get nodes
kubectl get pods -n kube-system
helm version
export POLARIS_DB_PASSWORD='polaris'
./platform/scripts/03-0-deploy-platform.sh
./platform/scripts/04-validate-platform.sh
./platform/scripts/03-1-deploy-kafka.sh
```

Then continue with Polaris bootstrap and Spark/Airflow reference workloads.

Cleanup:

```bash
./platform/scripts/06-cleanup-platform.sh
./infra/aws-proto/destroy-infra.sh
```

## Next Best Work

The next useful implementation path is:

1. Re-run from a clean infra/platform baseline in WSL.
2. Confirm `values-strimzi-operator.yaml` has `createGlobalResources: true`.
3. Confirm Polaris is deployed at `1.3.0-incubating`.
4. Deploy and validate Kafka again.
5. Install Polaris CLI locally and run `03-5-bootstrap-polaris-reference.sh`.
6. Stabilize Polaris principal secret handling for Spark workloads.
7. Move to Spark batch reference workload validation.
8. Then validate Spark streaming and Airflow orchestration.

## Important WSL Decision

The Windows copy and WSL copy do not sync automatically.

Decision:

- treat `/home/ubuntu/work/dc-platform` as the primary working repo
- open it from Windows VS Code using Remote - WSL
- avoid editing `/mnt/c/Users/baljeet/Documents/projects/dc-platform` except as an old backup
