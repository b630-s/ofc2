# Workload Reference Conventions

This document defines the conventions that the reference workloads use on top of the current AWS prototype platform.

It is intended to make the Kafka, Spark, Airflow, and Polaris examples consistent with one another before more workload assets are added.

## Scope

These conventions apply to the sample and reference assets under `reference-workloads/`.

They are a starting point for teams building on the platform, not a strict requirement for every future project repository.

## Namespaces And Runtime Identity

Reference workloads should use these namespaces:

- `kafka`
- `spark`
- `airflow`
- `polaris`

Reference workloads should use these service accounts:

- `spark/spark-sa`
- `airflow/airflow-sa`
- `polaris/polaris-sa`

AWS access should use IRSA only.

Reference workload compute should prefer the `workload` node group.

Examples:

- Kafka reference broker and controller pods
- Kafka test client pod
- Spark driver pods
- Spark executor pods

Shared platform services remain on the `core` node group.

## Bucket And Prefix Layout

Current bucket:

- `dc-platform-bss-proto-lakehouse-7901580-us-east-1`

Reference prefix layout:

- `s3://dc-platform-bss-proto-lakehouse-7901580-us-east-1/reference/raw/orders/`
- `s3://dc-platform-bss-proto-lakehouse-7901580-us-east-1/reference/bronze/orders_raw/`
- `s3://dc-platform-bss-proto-lakehouse-7901580-us-east-1/reference/silver/orders_daily/`
- `s3://dc-platform-bss-proto-lakehouse-7901580-us-east-1/reference/checkpoints/orders_raw_to_bronze/`
- `s3://dc-platform-bss-proto-lakehouse-7901580-us-east-1/reference/airflow/`

These keep all reference artifacts clearly separated from future project-owned paths.

## Kafka Conventions

Reference Kafka cluster:

- cluster name: `reference-kafka`
- bootstrap service: `reference-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092`

Reference topics:

- `orders_raw`
- `orders_dlq`

The initial reference pattern is:

- `orders_raw` receives sample order events
- `orders_dlq` is reserved for failed or malformed messages

## Polaris Conventions

Reference Polaris catalog conventions:

- catalog name: `reference`
- namespace names:
  - `bronze`
  - `silver`

Planned reference table names:

- `reference.bronze.orders_raw`

The bucket layout above should map to the default base locations used by this catalog.

## Spark Conventions

Reference Spark workloads should:

- run in namespace `spark`
- use service account `spark-sa`
- use IRSA instead of static AWS credentials
- treat Polaris as the Iceberg catalog entry point
- keep driver and executor sizing intentionally small in the prototype

Important current limitation:

- the shared Spark smoke test lives under `reference-workloads/shared/spark/manifests/`
- orders-specific SparkApplication manifests live under `reference-workloads/orders-reference/spark/manifests/`
- they are reference templates
- they still need a validated Spark runtime packaging choice for Iceberg and Polaris dependencies before they should be treated as runnable end-to-end examples
- they also require Polaris principal credentials to be injected before apply

The current staged Spark reference flow is:

- step 1:
  - read `orders_raw` from Kafka
  - write raw parquet under `reference/raw/orders/`
- step 2:
  - read raw parquet
  - write curated parquet under `reference/curated/orders/`
- step 3:
  - read curated parquet
  - write `reference.bronze.orders_raw`

Current Spark template assumptions:

- the Polaris REST catalog `warehouse` value is the catalog name: `reference`
- Spark should use Iceberg REST settings compatible with Polaris, including:
  - `catalog-impl=org.apache.iceberg.rest.RESTCatalog`
  - `scope=PRINCIPAL_ROLE:ALL`
  - access delegation header `X-Iceberg-Access-Delegation=vended-credentials`
  - principal credential injection before template render

## Airflow Conventions

Reference Airflow assets should:

- live in namespace `airflow`
- use service account `airflow-sa`
- orchestrate Spark jobs rather than embedding infrastructure logic

Airflow orchestration for the staged orders reference flow is not currently the primary validated path.

## Monitoring Boundary

Shared monitoring stays in the platform layer:

- Prometheus
- Grafana
- shared cluster and platform observability

Reference workloads may later add:

- workload-specific smoke tests
- workload-specific dashboards
- workload-specific validation scripts

Those should live under `reference-workloads/` rather than changing the platform monitoring baseline.

## Reference Flow

The intended end-to-end reference path is:

1. sample producer writes to `orders_raw`
2. Spark writes raw parquet under `reference/raw/orders/`
3. Spark transforms raw parquet into curated parquet
4. Spark writes `reference.bronze.orders_raw`
