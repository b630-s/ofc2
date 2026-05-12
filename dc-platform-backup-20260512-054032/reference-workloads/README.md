# Reference Workloads

This folder contains reference and sample workload assets that demonstrate how teams should use the platform.

It is not intended to be the long-term home for every business pipeline in every project.

Current implemented slice:

- shared Kafka baseline in `platform/kafka/`
  - one small Strimzi KRaft cluster sized for the current prototype environment
  - topics `orders_raw` and `orders_dlq`
  - optional test client pod
  - dedicated shared deploy script: `platform/scripts/03-1-deploy-kafka.sh`

Current workload-layer scripts:

- `reference-workloads/orders-reference/scripts/load-orders-events-to-kafka.sh`
- `reference-workloads/orders-reference/scripts/check-orders-events-in-kafka.sh`
- shared Polaris bootstrap remains in `platform/scripts/03-5-bootstrap-polaris-reference.sh`

Current reference workload layout:

- shared runtime validation assets in `reference-workloads/shared/`
- orders-specific reference assets in `reference-workloads/orders-reference/`
- sample input data in `reference-workloads/data/`
- shared Kafka baseline assets in `platform/kafka/`

Reference conventions are documented in:

- [docs/workload-reference.md](/C:/Users/baljeet/Documents/projects/dc-platform/docs/workload-reference.md)

Platform monitoring note:

- Prometheus and Grafana stay in the platform layer and are installed by `platform/scripts/03-0-deploy-platform.sh`
- `reference-workloads/` should only add workload-specific checks or dashboards later if needed

Current readiness note:

- Kafka reference deployment is implemented
- the orders reference workload now groups its Spark jobs, Spark manifests, Airflow DAGs, and image build files together
- Spark and Airflow reference assets still need further runtime hardening around packaging, secrets, and full validation

Deploy the shared Kafka slice with:

```bash
./platform/scripts/03-1-deploy-kafka.sh
```

Run the orders-reference scripts individually in sequence from the orders README.
