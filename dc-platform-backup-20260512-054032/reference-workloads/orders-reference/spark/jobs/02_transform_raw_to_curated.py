import argparse

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, from_json, to_timestamp
from pyspark.sql.types import DoubleType, StringType, StructField, StructType


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-path", required=True)
    parser.add_argument("--curated-path", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    spark = SparkSession.builder.appName("reference-orders-transform-raw-to-curated").getOrCreate()

    schema = StructType(
        [
            StructField("event_id", StringType(), True),
            StructField("tenant_id", StringType(), True),
            StructField("event_type", StringType(), True),
            StructField("order_id", StringType(), True),
            StructField("amount", DoubleType(), True),
            StructField("currency", StringType(), True),
            StructField("event_time", StringType(), True),
        ]
    )

    raw_df = spark.read.parquet(args.raw_path)

    curated_df = (
        raw_df.withColumn("json_data", from_json(col("message_value"), schema))
        .select(
            col("json_data.event_id").alias("event_id"),
            col("json_data.tenant_id").alias("tenant_id"),
            col("json_data.event_type").alias("event_type"),
            col("json_data.order_id").alias("order_id"),
            col("json_data.amount").alias("amount"),
            col("json_data.currency").alias("currency"),
            to_timestamp(col("json_data.event_time")).alias("event_ts"),
            col("kafka_timestamp"),
            col("ingestion_timestamp"),
            current_timestamp().alias("curated_timestamp"),
        )
        .filter(col("event_id").isNotNull())
        .filter(col("tenant_id").isNotNull())
        .filter(col("order_id").isNotNull())
    )

    curated_df.write.mode("overwrite").parquet(args.curated_path)

    spark.stop()


if __name__ == "__main__":
    main()
