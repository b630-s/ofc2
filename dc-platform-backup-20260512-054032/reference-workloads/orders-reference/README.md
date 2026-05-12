# Orders Reference Workload

This folder contains the orders reference workload assets, including:

- Spark job code
- SparkApplication manifests
- use-case-specific workload scripts
- the repo-owned Spark image Dockerfile

The goal is to move away from ConfigMap-mounted job code over time and toward a more production-style model where:

- the Spark runtime image is pinned and owned by this repo
- reference jobs are baked into the image
- Airflow submits Spark jobs that all use the same image
- Polaris and Iceberg configuration remain part of the SparkApplication runtime config

## Image Build Pattern

The image build intentionally stays simple for the current iteration:

- base image: `docker.io/library/spark:3.5.3-python3`
- baked-in job code copied from `spark/jobs/` into `/opt/dc-platform/jobs`
- build-time resolution of generic Spark Kafka and Iceberg runtime dependencies into `/opt/spark/jars`

That keeps the base image more portable while leaving cloud-specific runtime dependencies in the SparkApplication specs.

## Spark Job Code

- `spark/jobs/01_read_kafka_to_raw.py`
- `spark/jobs/02_transform_raw_to_curated.py`
- `spark/jobs/03_write_curated_to_iceberg.py`

These numbered jobs are the current canonical staged orders flow.

The orders workload targets:

- Kafka topic: `orders_raw`
- raw landing path under `reference/raw/`
- curated parquet path under `reference/curated/`
- Iceberg target table in the Polaris `reference` catalog

## Polaris For Orders

The shared Polaris bootstrap remains in `platform/`, but the orders-specific table model belongs to this use case.

Shared Polaris bootstrap creates:

- catalog `reference`
- namespaces `bronze` and `silver`
- Spark principal and role wiring needed for runtime access

The orders-specific tables are intended to be created by Spark jobs during first successful write, not by the shared Polaris bootstrap script.

Current orders table ownership:

- `reference.bronze.orders_raw`
  - current default Iceberg target in the staged image-baked path
  - written by `spark/jobs/03_write_curated_to_iceberg.py` unless overridden

Current ownership split:

- `platform/scripts/03-5-bootstrap-polaris-reference.sh`
  - shared catalog, namespace, and access bootstrap

- `reference-workloads/orders-reference/`
  - use-case-specific Spark jobs and manifests
  - use-case-specific Bronze and Silver table meaning

So the platform layer creates the shared Polaris structure, and the orders workload creates its own tables through Spark.

## Execution Sequence

Shared prerequisites live under `platform/`:

1. `platform/scripts/02-connect-cluster.sh`
2. `platform/scripts/03-0-deploy-platform.sh`
3. `platform/scripts/03-1-deploy-kafka.sh`
4. `platform/scripts/03-5-bootstrap-polaris-reference.sh`

Then use the orders-reference entrypoints in this folder:

1. `./reference-workloads/orders-reference/scripts/load-orders-events-to-kafka.sh`
2. `./reference-workloads/orders-reference/scripts/check-orders-events-in-kafka.sh`
3. `./reference-workloads/orders-reference/scripts/create-orders-polaris-runtime-secret.sh`
4. `./reference-workloads/orders-reference/scripts/deploy-orders-kafka-to-raw.sh`
5. `./reference-workloads/orders-reference/scripts/deploy-orders-raw-to-curated.sh`
6. `./reference-workloads/orders-reference/scripts/deploy-orders-curated-to-iceberg.sh`

Current intent:

- `scripts/load-orders-events-to-kafka.sh` loads sample order events into Kafka topic `orders_raw`
- `scripts/check-orders-events-in-kafka.sh` verifies the events are present in Kafka
- `scripts/create-orders-polaris-runtime-secret.sh` stores the orders runtime Polaris principal credentials in the `spark` namespace
- `scripts/deploy-orders-kafka-to-raw.sh` submits the Kafka-to-raw SparkApplication
- `scripts/deploy-orders-raw-to-curated.sh` submits the raw-to-curated SparkApplication
- `scripts/deploy-orders-curated-to-iceberg.sh` submits the curated-to-Iceberg SparkApplication

These scripts assume shared Kafka and shared Polaris reference bootstrap are already complete.

To load the sample order events into Kafka:

```bash
INSTALL_KAFKA_TEST_CLIENT=true ./platform/scripts/03-1-deploy-kafka.sh
./reference-workloads/orders-reference/scripts/load-orders-events-to-kafka.sh
```

The loader uses:

- local file `reference-workloads/data/sample-events.json`
- Kafka topic `orders_raw`
- client pod `kafka-test-client` in namespace `kafka`

To verify the events are present in Kafka before running Spark:

```bash
./reference-workloads/orders-reference/scripts/check-orders-events-in-kafka.sh
```

Optional override:

```bash
MAX_MESSAGES=5 ./reference-workloads/orders-reference/scripts/check-orders-events-in-kafka.sh
```

## Shared Prerequisite Notes

### Shared Kafka Verification

```bash
kubectl get kafka -n kafka
kubectl get kafkanodepool -n kafka
kubectl get kafkatopic -n kafka
kubectl get pods -n kafka -o wide
```

### Kafka / Strimzi Troubleshooting

```bash
kubectl logs -n platform-system deployment/strimzi-cluster-operator --tail=300
kubectl describe kafka reference-kafka -n kafka
kubectl get kafkanodepool -n kafka -o yaml
kubectl get events -n kafka --sort-by=.lastTimestamp
kubectl get pvc -n kafka
```

### Install Polaris CLI

```bash
sudo apt update
sudo apt install -y openjdk-21-jre-headless jq curl tar
java --version
jq --version
mkdir -p ~/tools
cd ~/tools
curl -L https://downloads.apache.org/incubator/polaris/1.3.0-incubating/polaris-bin-1.3.0-incubating.tgz | tar xz
mkdir -p ~/.local/bin
cat > ~/.local/bin/polaris <<'EOF'
#!/usr/bin/env bash
exec "$HOME/tools/polaris-bin-1.3.0-incubating/bin/admin" "$@"
EOF
chmod +x ~/.local/bin/polaris
export PATH="$HOME/.local/bin:$HOME/tools/polaris-bin-1.3.0-incubating/bin:$PATH"
polaris --help
```

### Polaris Bootstrap Inputs

```bash
export POLARIS_ADMIN_CLIENT_ID='<admin-client-id>'
export POLARIS_ADMIN_CLIENT_SECRET='<admin-client-secret>'
export POLARIS_ROLE_ARN='<polaris-irsa-role-arn>'
```

Get the role ARN from Terraform output:

```bash
cd ~/work/dc-platform/infra/aws-proto
terraform output -raw polaris_s3_role_arn
```

Find the Polaris admin credentials from secrets in the `polaris` namespace:

```bash
kubectl get secrets -n polaris
kubectl get secret <secret-name> -n polaris -o json | jq -r '.data | keys[]'
kubectl get secret <secret-name> -n polaris -o jsonpath='{.data.<client-id-key>}' | base64 --decode
kubectl get secret <secret-name> -n polaris -o jsonpath='{.data.<client-secret-key>}' | base64 --decode
```

Run the shared bootstrap with:

```bash
./platform/scripts/03-5-bootstrap-polaris-reference.sh
```

The shared bootstrap prints the reference Spark principal credentials when it creates them. Store those in the runtime Kubernetes secret used by the orders flow:

```bash
export POLARIS_USER_CLIENT_ID='<reference-spark-client-id>'
export POLARIS_USER_CLIENT_SECRET='<reference-spark-client-secret>'
./reference-workloads/orders-reference/scripts/create-orders-polaris-runtime-secret.sh
```

## Build

From repo root:

```bash
docker build -t dc-platform-reference-spark:0.1 reference-workloads/orders-reference
```

The Docker build resolves and bakes in these Spark-side dependencies:

- Kafka source support for Spark 3.5
- Iceberg Spark runtime for Spark 3.5

The SparkApplication manifests still supply the AWS-specific runtime pieces for the current environment:

- Hadoop AWS / S3A support
- Iceberg AWS bundle for the Polaris + S3 path

Tag and push later to your registry:

```bash
docker tag dc-platform-reference-spark:0.1 <your-registry>/dc-platform-reference-spark:0.1
docker push <your-registry>/dc-platform-reference-spark:0.1
```

## Intended Spark Usage

The intended staged Spark pattern is:

1. Kafka to raw parquet
2. raw parquet to curated parquet
3. curated parquet to Iceberg

The image-baked jobs use the same image and different `mainApplicationFile` values:

- `local:///opt/dc-platform/jobs/01_read_kafka_to_raw.py`
- `local:///opt/dc-platform/jobs/02_transform_raw_to_curated.py`
- `local:///opt/dc-platform/jobs/03_write_curated_to_iceberg.py`

## SparkApplication Manifests

The orders reference currently includes:

- [spark-app-kafka-to-raw.yaml](/home/ubuntu/work/dc-platform/reference-workloads/orders-reference/spark/manifests/spark-app-kafka-to-raw.yaml)
- [spark-app-raw-to-curated.yaml](/home/ubuntu/work/dc-platform/reference-workloads/orders-reference/spark/manifests/spark-app-raw-to-curated.yaml)
- [spark-app-curated-to-iceberg.yaml](/home/ubuntu/work/dc-platform/reference-workloads/orders-reference/spark/manifests/spark-app-curated-to-iceberg.yaml)
- shared [spark-app-sparkpi.yaml](/home/ubuntu/work/dc-platform/reference-workloads/shared/spark/manifests/spark-app-sparkpi.yaml)

The staged path uses the repo-owned Spark image and the baked-in jobs:

- `01_read_kafka_to_raw.py`
- `02_transform_raw_to_curated.py`
- `03_write_curated_to_iceberg.py`

There is also a SparkPi smoke-test manifest under `reference-workloads/shared/spark/manifests/`. That is the cleanest first validation of:

- Spark Operator submission
- cluster-mode Spark execution
- image pull behavior
- driver and executor scheduling

Apply SparkPi like this:

```bash
export REFERENCE_SPARK_IMAGE='<your-registry>/dc-platform-reference-spark:0.1'
envsubst < reference-workloads/shared/spark/manifests/spark-app-sparkpi.yaml | kubectl apply -f -
```

Apply the staged orders manifests like this:

```bash
export REFERENCE_SPARK_IMAGE='<your-registry>/dc-platform-reference-spark:0.1'
export POLARIS_USER_CLIENT_ID='<reference-spark-client-id>'
export POLARIS_USER_CLIENT_SECRET='<reference-spark-client-secret>'
./reference-workloads/orders-reference/scripts/create-orders-polaris-runtime-secret.sh
./reference-workloads/orders-reference/scripts/deploy-orders-kafka-to-raw.sh
./reference-workloads/orders-reference/scripts/deploy-orders-raw-to-curated.sh
./reference-workloads/orders-reference/scripts/deploy-orders-curated-to-iceberg.sh
```

## Airflow Orchestration

Airflow is the intended orchestrator for the staged orders path.

Use:

- [dag-orders-reference.py](/home/ubuntu/work/dc-platform/reference-workloads/orders-reference/airflow/dag-orders-reference.py)

The DAG runs the three SparkApplication steps in order:

1. Kafka to raw parquet
2. raw parquet to curated parquet
3. curated parquet to Iceberg through Polaris

For Airflow, set the image as an Airflow Variable:

```text
reference_spark_image=<your-registry>/dc-platform-reference-spark:0.1
```

The DAG loads the same manifest files used by the shell scripts, replaces the image field from the Airflow Variable at runtime, and adds a run-specific SparkApplication name suffix so repeated DAG runs do not collide.

Before running the DAG, make sure:

- the shared platform and Kafka prerequisites are complete
- the runtime secret `reference-polaris-spark-credentials` exists in namespace `spark`
- the Airflow deployment includes the `orders-reference/airflow` DAG file and the neighboring `spark/manifests` directory

Useful checks:

```bash
kubectl get sparkapplications -n spark
kubectl describe sparkapplication reference-orders-kafka-to-raw -n spark
kubectl get pods -n spark -l sparkoperator.k8s.io/app-name=reference-orders-kafka-to-raw
```

## Layout

Current layout:

```text
orders-reference/
  Dockerfile
  README.md
  scripts/
  spark/
    manifests/
    jobs/
  airflow/
```

## Notes

- The image build files now live at the use-case root instead of a separate `spark-image/` folder.
- `spark/jobs/` is the single source of truth for Spark job code in this reference workload.
- The base image keeps generic Spark dependencies baked in, while the manifests continue to carry AWS-specific runtime packages for the current deployment target.
- The Docker build still needs network access to resolve Maven artifacts during image creation.
