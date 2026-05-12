from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.spark_kubernetes import (
    SparkKubernetesOperator,
)
import yaml


MANIFESTS_DIR = Path(__file__).resolve().parents[1] / "spark" / "manifests"
AIRFLOW_IMAGE_TEMPLATE = "{{ var.value.reference_spark_image }}"


def load_spark_application(filename: str) -> dict:
    manifest_path = MANIFESTS_DIR / filename
    spec = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))

    spec["spec"]["image"] = AIRFLOW_IMAGE_TEMPLATE
    spec["metadata"]["name"] = f"{spec['metadata']['name']}-{{{{ ts_nodash }}}}"

    return spec


with DAG(
    dag_id="orders_reference_staged",
    start_date=datetime(2026, 4, 1),
    catchup=False,
    dagrun_timeout=timedelta(minutes=30),
    schedule=None,
    tags=["reference", "spark", "orders"],
) as dag:
    run_kafka_to_raw = SparkKubernetesOperator(
        task_id="orders_kafka_to_raw",
        namespace="spark",
        template_spec=load_spark_application("spark-app-kafka-to-raw.yaml"),
        get_logs=True,
    )

    run_raw_to_curated = SparkKubernetesOperator(
        task_id="orders_raw_to_curated",
        namespace="spark",
        template_spec=load_spark_application("spark-app-raw-to-curated.yaml"),
        get_logs=True,
    )

    run_curated_to_iceberg = SparkKubernetesOperator(
        task_id="orders_curated_to_iceberg",
        namespace="spark",
        template_spec=load_spark_application("spark-app-curated-to-iceberg.yaml"),
        get_logs=True,
    )

    run_kafka_to_raw >> run_raw_to_curated >> run_curated_to_iceberg
