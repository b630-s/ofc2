import argparse

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kafka-bootstrap", required=True)
    parser.add_argument("--topic", default="orders_raw")
    parser.add_argument("--raw-path", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    spark = SparkSession.builder.appName("reference-orders-read-kafka-to-raw").getOrCreate()

    df = (
        spark.read.format("kafka")
        .option("kafka.bootstrap.servers", args.kafka_bootstrap)
        .option("subscribe", args.topic)
        .option("startingOffsets", "earliest")
        .option("endingOffsets", "latest")
        .load()
    )

    raw_df = df.select(
        col("key").cast("string").alias("message_key"),
        col("value").cast("string").alias("message_value"),
        col("topic"),
        col("partition"),
        col("offset"),
        col("timestamp").alias("kafka_timestamp"),
        current_timestamp().alias("ingestion_timestamp"),
    )

    raw_df.write.mode("append").parquet(args.raw_path)

    spark.stop()


if __name__ == "__main__":
    main()
