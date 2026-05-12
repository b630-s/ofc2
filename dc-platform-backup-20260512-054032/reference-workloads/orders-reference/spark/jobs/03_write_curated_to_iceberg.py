import argparse
import os

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, to_date


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--curated-path", required=True)
    parser.add_argument("--table", default="reference.bronze.orders_raw")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    client_id = os.environ.get("POLARIS_USER_CLIENT_ID", "")
    client_secret = os.environ.get("POLARIS_USER_CLIENT_SECRET", "")

    builder = SparkSession.builder.appName("reference-orders-write-curated-to-iceberg")
    if client_id and client_secret:
        builder = builder.config(
            "spark.sql.catalog.reference.credential",
            f"{client_id}:{client_secret}",
        )

    spark = builder.getOrCreate()

    df = (
        spark.read.parquet(args.curated_path)
        .withColumn("event_date", to_date(col("event_ts")))
        .dropDuplicates(["event_id"])
    )

    namespace = args.table.rsplit(".", 1)[0]
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {namespace}")

    df.writeTo(args.table).using("iceberg").createOrReplace()

    spark.stop()


if __name__ == "__main__":
    main()
