# Developer Guide

## Purpose

This guide is for team members who need to use the shared AWS prototype environment after the infrastructure and platform have already been deployed.

Use this document when you need to:

- connect your own AWS user to the shared EKS cluster
- verify you can see the platform services
- understand the shared namespaces and service boundaries
- start building and running Spark workloads
- find the important runtime details for Kafka, Polaris, and S3-backed storage

This guide assumes:

- the AWS infrastructure has already been created
- the platform baseline has already been deployed
- you are joining as a developer or operator in the same AWS account

## What You Need From The Team

Before you start, ask the environment owner for the following:

- AWS account ID
- AWS region
- EKS cluster name
- repo URL and branch or commit to use
- the current `infra/aws-proto/terraform.tfvars` values or a sanitized copy of the important ones
- confirmation that your AWS user or role has been granted access to the EKS cluster
- confirmation that your Kubernetes RBAC has been set up

You should also ask for these platform-specific details:

- lakehouse bucket name
- Polaris catalog name
- Polaris namespaces already created
- image registry or repository to use for Spark images
- whether you should reuse the shared Spark runtime service account or use a separate one
- any required runtime secret names

For the current prototype, the most important shared values are usually:

- cluster name: `dc-platform-bss-eks-proto`
- AWS region: `us-east-1`
- Spark namespace: `spark`
- Kafka namespace: `kafka`
- Airflow namespace: `airflow`
- Polaris namespace: `polaris`
- monitoring namespace: `monitoring`
- platform namespace: `platform-system`
- Polaris catalog: `reference`
- Polaris namespaces: `bronze` and `silver`

## Current Shared Environment Values

The current prototype uses these concrete shared names and values.

### Core Environment Values

- cluster name: `dc-platform-bss-eks-proto`
- AWS region: `us-east-1`
- lakehouse bucket: `dc-platform-bss-proto-lakehouse-7901580-us-east-1`
- Polaris catalog: `reference`
- Polaris namespaces: `bronze`, `silver`

### Shared IAM Role Names

These are the main hardcoded IAM role names used by the current prototype:

- EKS cluster role: `dc-platform-bss-eks-cluster-role`
- EKS node role: `dc-platform-bss-eks-node-role`
- EBS CSI role: `dc-platform-bss-ebs-csi-role`
- Polaris S3 role: `dc-platform-bss-polaris-s3-role`
- Spark S3 role: `dc-platform-bss-spark-s3-role`
- Airflow S3 role: `dc-platform-bss-airflow-s3-role`

### Shared Runtime Service Accounts

These Kubernetes service accounts are the intended runtime identities for the shared platform:

- `spark/spark-sa`
- `airflow/airflow-sa`
- `polaris/polaris-sa`

In the current EKS implementation, the platform deployment flow annotates these service accounts with the corresponding IAM role ARNs through IRSA.

Check the current live values in:

- [SETUP_README.md](/home/ubuntu/work/dc-platform/SETUP_README.md:1)
- [docs/architecture.md](/home/ubuntu/work/dc-platform/docs/architecture.md:1)
- [infra/aws-proto/terraform.tfvars](/home/ubuntu/work/dc-platform/infra/aws-proto/terraform.tfvars:1)

## Access Model

You need two layers of access:

### 1. AWS Access

Your AWS identity must be able to:

- call `eks:DescribeCluster`
- run `aws eks update-kubeconfig`
- inspect node groups and cluster details when troubleshooting
- optionally pull and push container images if the team uses a shared registry such as ECR

### 2. Kubernetes Access

AWS access alone is not enough. You also need Kubernetes authorization inside the cluster.

At minimum, you should have:

- read access to the shared platform namespaces
- write access to the namespace where you will submit Spark workloads

For this prototype, the most practical default is:

- read access in `platform-system`, `monitoring`, `kafka`, `airflow`, and `polaris`
- write access in `spark`

If `aws eks update-kubeconfig` works but `kubectl get pods -A` returns authorization errors, the problem is Kubernetes access, not AWS login.

## Local Tooling

Install the operator prerequisites from:

- [SETUP_README.md](/home/ubuntu/work/dc-platform/SETUP_README.md:370)

At minimum, you need:

- AWS CLI
- Terraform
- `kubectl`
- Helm
- `jq`
- `curl`
- `tar`
- Java 21 runtime for Polaris admin bootstrap tasks
- `envsubst` for some Spark manifest flows
- Docker if you want to build Spark images locally

## Clone The Repo

Clone the repository and move into it:

```bash
git clone <repo-url>
cd dc-platform
```

If your team uses a specific branch for the deployed environment:

```bash
git checkout <branch-or-tag>
```

## Configure AWS Credentials

Use your own AWS user or assumed role credentials. For example:

```bash
aws configure
```

Or, if your team uses named profiles:

```bash
export AWS_PROFILE=<your-profile>
```

Verify access:

```bash
aws sts get-caller-identity
```

## Connect To The Shared EKS Cluster

The repo provides a helper script:

```bash
./platform/scripts/02-connect-cluster.sh
```

That script reads the cluster details from the repo and updates your kubeconfig.

You can also connect directly:

```bash
aws eks update-kubeconfig --region us-east-1 --name dc-platform-bss-eks-proto
```

After that, verify connectivity:

```bash
kubectl get nodes
kubectl get ns
kubectl get pods -A
```

If that fails:

- check your AWS credentials
- check that the cluster name and region are correct
- confirm that your IAM identity has EKS access
- confirm that your Kubernetes RBAC has been granted

## Shared Platform Layout

The current platform uses these namespaces:

- `platform-system`
  Shared operators and core platform controllers such as Strimzi and Spark Operator.
- `monitoring`
  Prometheus and Grafana.
- `kafka`
  Shared Kafka cluster resources and test client pod.
- `spark`
  Spark workloads, SparkApplications, and Spark runtime secrets.
- `airflow`
  Shared Airflow components.
- `polaris`
  Shared Polaris catalog service and backing PostgreSQL.
- `ingress-nginx`
  Optional ingress layer when enabled.

The current scheduling model uses two node groups:

- `core`
  Shared platform services run here.
- `workload`
  Data-path and tenant-style workloads run here.

That separation matters when you inspect manifests or author new runtime configurations.

## Verify The Shared Environment

Before you start developing, confirm the shared environment is healthy enough to use.

Basic checks:

```bash
kubectl get nodes -L NodeGroupType,WorkloadClass
kubectl get pods -A
kubectl get sa -A | egrep 'spark-sa|airflow-sa|polaris-sa'
```

Platform checks:

```bash
kubectl get pods -n platform-system
kubectl get pods -n monitoring
kubectl get pods -n airflow
kubectl get pods -n polaris
kubectl get pods -n spark
kubectl get pods -n kafka
```

Kafka checks:

```bash
kubectl get kafka -n kafka
kubectl get kafkanodepool -n kafka
kubectl get kafkatopic -n kafka
```

Spark checks:

```bash
kubectl get sparkapplications -n spark
kubectl get pods -n spark
```

Polaris checks:

```bash
kubectl get pods -n polaris
kubectl get svc -n polaris
```

Monitoring checks:

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

## Shared Runtime Details You Will Need

To build useful workloads, you need a small set of shared runtime facts.

### Object Storage

Ask the environment owner for:

- lakehouse bucket name
- expected path prefixes under the bucket
- whether any specific folder conventions must be followed

The current platform treats object storage as an S3-compatible interface, but in this AWS prototype the backing store is Amazon S3.

The shared bucket is expected to back:

- raw data
- curated data
- Iceberg table data
- future checkpoints and workflow artifacts

### Polaris

Ask for:

- Polaris catalog name
- Polaris namespaces already created
- the expected principal model for developers and workloads
- whether you will get your own Polaris principal or share one

For the current shared reference setup, the common values are:

- catalog: `reference`
- namespaces: `bronze`, `silver`

Spark workloads should treat Polaris as the catalog abstraction for Iceberg access rather than hard-coding direct storage-only table assumptions.

### Spark Runtime Secrets

Ask for:

- the name of the Kubernetes secret containing runtime Polaris credentials
- the process for creating a new secret if you need a separate principal

Do not assume you should reuse production-like secrets across the whole team unless the environment owner has explicitly chosen that.

### Container Registry

Ask for:

- which image registry to use
- repository naming conventions
- whether you can push directly or need CI to publish images

## Building Spark Workloads

The best starting point is the reference workload:

- [reference-workloads/orders-reference/README.md](/home/ubuntu/work/dc-platform/reference-workloads/orders-reference/README.md:1)

That folder shows the intended pattern:

- package Spark job code into a repo-owned image
- submit jobs as SparkApplication resources
- use runtime configuration for environment-specific settings
- read from Kafka or parquet
- write to parquet or Iceberg through Polaris

The same broad model should hold for new team workloads:

- Spark batch jobs
- Spark streaming jobs
- Airflow DAG-driven orchestration
- S3-backed data paths
- Iceberg tables managed through Polaris

### Build A Local Spark Image

From the repo root:

```bash
docker build -t dc-platform-reference-spark:0.1 reference-workloads/orders-reference
```

If your team uses a shared registry:

```bash
docker tag dc-platform-reference-spark:0.1 <registry>/dc-platform-reference-spark:0.1
docker push <registry>/dc-platform-reference-spark:0.1
```

### Submit Existing Reference Jobs

The shared orders reference sequence is:

1. load sample events into Kafka
2. verify the Kafka events
3. create the Polaris runtime secret in `spark`
4. deploy Kafka-to-raw
5. deploy raw-to-curated
6. deploy curated-to-Iceberg

The helper scripts are:

- `reference-workloads/orders-reference/scripts/load-orders-events-to-kafka.sh`
- `reference-workloads/orders-reference/scripts/check-orders-events-in-kafka.sh`
- `reference-workloads/orders-reference/scripts/create-orders-polaris-runtime-secret.sh`
- `reference-workloads/orders-reference/scripts/deploy-orders-kafka-to-raw.sh`
- `reference-workloads/orders-reference/scripts/deploy-orders-raw-to-curated.sh`
- `reference-workloads/orders-reference/scripts/deploy-orders-curated-to-iceberg.sh`

### Airflow Development Expectations

Airflow is available for workflow orchestration, but DAGs should orchestrate jobs rather than embed infrastructure setup logic.

Preferred pattern:

- Airflow triggers Spark jobs or related validations
- runtime configuration stays externalized
- AWS access continues to flow through Kubernetes service accounts and IRSA

## Access Pattern For Shared Services

Most shared services are internal to the cluster right now.

Typical access methods are:

- `kubectl`
- `kubectl logs`
- `kubectl describe`
- `kubectl port-forward`
- AWS Console for infrastructure-side verification

Do not assume dashboards or services are internet-exposed by default.

If broader UI access is needed for a service such as Airflow, Grafana, or Polaris, that should be handled explicitly through ingress, load balancers, or a team-approved access path.

## Engineering Guidance

### Do

- use the provided namespaces
- use the provided service accounts unless the environment owner tells you otherwise
- rely on IRSA for AWS access
- assume S3-backed storage
- assume Iceberg plus Polaris for table access
- keep workflows Kubernetes-native
- keep job configuration externalized
- use unique image tags, job names, and output paths when working in the shared environment

### Do Not

- do not embed AWS access keys in code, manifests, or notebooks
- do not assume local disk persistence
- do not assume services are internet-exposed by default
- do not overwrite shared runtime secrets casually
- do not assume every installed operator already implies a fully provisioned runtime for your use case

### Inspect Running Spark Jobs

Useful commands:

```bash
kubectl get sparkapplications -n spark
kubectl describe sparkapplication <name> -n spark
kubectl get pods -n spark
kubectl logs -n spark <driver-pod-name>
```

If a SparkApplication creates executor pods, inspect both driver and executor logs.

## Recommended Development Workflow

For a new team member, the safest path is:

1. connect to the cluster
2. verify the shared platform services are healthy
3. read the reference workload docs
4. run or inspect the existing SparkApplications
5. build a copy of the reference Spark image
6. duplicate one reference SparkApplication manifest and adapt it
7. use a separate image tag for your own iteration

If your team is sharing one `spark` namespace, be disciplined about:

- unique SparkApplication names
- unique output paths
- clear image tags
- not overwriting shared secrets or manifests casually

## What To Ask The Environment Owner Before Running New Workloads

Before you submit custom jobs, confirm:

- where your output data should go in the bucket
- whether you should create new Polaris namespaces or reuse existing ones
- whether you should use a shared runtime principal or a dedicated one
- whether there are naming conventions for SparkApplication resources
- whether there are cost limits or node-group capacity constraints you should respect

This matters because the current environment is a shared prototype, not a fully isolated per-developer sandbox.

## Troubleshooting

### You Can Log Into AWS But `kubectl` Fails

Likely cause:

- missing Kubernetes access mapping or RBAC

Checks:

```bash
aws sts get-caller-identity
aws eks describe-cluster --region us-east-1 --name dc-platform-bss-eks-proto
kubectl auth can-i get pods -A
```

### You Can Read The Cluster But Cannot Submit Spark Jobs

Likely cause:

- you have read access but not write access in `spark`

Checks:

```bash
kubectl auth can-i create sparkapplications.sparkoperator.k8s.io -n spark
kubectl auth can-i create pods -n spark
```

### Spark Jobs Start But Cannot Reach S3 Or Polaris

Likely causes:

- wrong image tag
- missing runtime secret
- wrong service account
- missing IRSA annotation or wrong IAM policy
- wrong Polaris credentials

Checks:

```bash
kubectl get sa spark-sa -n spark -o yaml
kubectl get secret -n spark
kubectl describe sparkapplication <name> -n spark
kubectl logs -n spark <driver-pod-name>
```

### Kafka Is Not Available

Checks:

```bash
kubectl get kafka -n kafka
kubectl get kafkanodepool -n kafka
kubectl get pods -n kafka
kubectl logs -n platform-system deployment/strimzi-cluster-operator --tail=300
```

## Suggested Team Handoff Checklist

If you are the environment owner handing this cluster to teammates, share all of the following:

- repo URL and branch or commit
- AWS account ID
- AWS region
- EKS cluster name
- lakehouse bucket name
- active Polaris catalog and namespaces
- namespaces they are expected to use
- registry location for Spark images
- whether they should use shared or dedicated Polaris principals
- runtime secret names or the workflow for creating them
- the exact connect command
- the exact validation commands

A simple handoff message can include:

```bash
aws eks update-kubeconfig --region us-east-1 --name dc-platform-bss-eks-proto
kubectl get nodes
kubectl get ns
kubectl get pods -n spark
```

Plus:

- “Develop in namespace `spark`”
- “Use the `reference` Polaris catalog unless told otherwise”
- “Start from `reference-workloads/orders-reference/`”

## Related Docs

- [SETUP_README.md](/home/ubuntu/work/dc-platform/SETUP_README.md:1)
- [docs/architecture.md](/home/ubuntu/work/dc-platform/docs/architecture.md:1)
- [platform/scripts/README.md](/home/ubuntu/work/dc-platform/platform/scripts/README.md:1)
- [reference-workloads/orders-reference/README.md](/home/ubuntu/work/dc-platform/reference-workloads/orders-reference/README.md:1)
