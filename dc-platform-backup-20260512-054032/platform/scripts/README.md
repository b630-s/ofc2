# Platform Scripts

#SUMMARY COMMANDS: Start

This folder contains the canonical platform lifecycle scripts.
deploy infra
deploy platform
test workloads
clean up platform/workloads
destroy infra


cd ~/work/dc-platform
./platform/scripts/02-connect-cluster.sh
kubectl get nodes
kubectl get pods -n kube-system
helm version
export POLARIS_DB_PASSWORD='polaris'
./platform/scripts/03-0-deploy-platform.sh
./platform/scripts/03-1-deploy-kafka.sh
./platform/scripts/04-validate-platform.sh
./platform/scripts/03-5-bootstrap-polaris-reference.sh
kubectl get ns
kubectl get sa -A | egrep 'spark-sa|airflow-sa|polaris-sa'
kubectl get pods -A

Move to now refernce workloads, scripts dir.

#SUMMARY COMMANDS: End


# DETAILED COMMANDS BELOW
## Execution Order

From the repo root:

```bash
./infra/aws-proto/deploy-infra.sh --apply
./platform/scripts/02-connect-cluster.sh
kubectl get nodes
kubectl get pods -n kube-system
helm version
export POLARIS_DB_PASSWORD='polaris'
./platform/scripts/03-0-deploy-platform.sh
./platform/scripts/03-1-deploy-kafka.sh
./platform/scripts/04-validate-platform.sh
./platform/scripts/03-5-bootstrap-polaris-reference.sh
```

Cleanup later:

```bash
./platform/scripts/06-cleanup-platform.sh
./infra/aws-proto/destroy-infra.sh
```

## What Each Script Does

- `02-connect-cluster.sh`
  Updates kubeconfig so `kubectl` and Helm point to the EKS cluster named in `infra/aws-proto/terraform.tfvars`.

- `03-0-deploy-platform.sh`
  Installs namespaces, service accounts, Strimzi, Spark Operator, Airflow, Polaris, and Prometheus/Grafana.

- `03-1-deploy-kafka.sh`
  Deploys the shared Kafka cluster, node pools, and reference topics after the platform layer is installed.

- `04-validate-platform.sh`
  Validates nodes and installed platform services.

- `03-5-bootstrap-polaris-reference.sh`
  Bootstraps the shared reference Polaris catalog, namespaces, and Spark principal wiring after Polaris is installed.

- `06-cleanup-platform.sh`
  Removes platform services from Kubernetes without deleting AWS infrastructure.

## Before Running 03

1. Infra apply has completed successfully:
   `./infra/aws-proto/deploy-infra.sh --apply`

2. Your shell is connected to the EKS cluster:
   `./platform/scripts/02-connect-cluster.sh`

3. Quick cluster sanity check passes:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

4. Helm is installed:

```bash
helm version
```

If Helm is missing in CloudShell:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

5. Polaris database password is exported:

```bash
export POLARIS_DB_PASSWORD='polaris'
```

Then run:

```bash
./platform/scripts/03-0-deploy-platform.sh
```

## Notes

- `03-0-deploy-platform.sh` tries to resolve the Spark, Airflow, and Polaris IAM role ARNs from Terraform outputs automatically.
- If Terraform state is not available locally, export those role ARNs manually before running platform install.
- Airflow, Polaris PostgreSQL, and Prometheus currently assume AWS storage class `gp2` in this prototype.
- `06-cleanup-platform.sh` acts on the currently connected Kubernetes cluster, so verify kube context before deleting.


Misc:
apply just Strimzi again:

cd ~/work/dc-platform
helm upgrade --install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --namespace platform-system \
  --create-namespace \
  --version 0.51.0 \
  --values platform/values-strimzi-operator.yaml \
  --wait \
  --timeout 10m
