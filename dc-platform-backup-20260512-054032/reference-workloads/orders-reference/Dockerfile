FROM docker.io/library/spark:3.5.3-python3

USER root

ENV PYSPARK_PYTHON=python3
ENV PYTHONUNBUFFERED=1
ENV SPARK_EXTRA_PACKAGES="org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.3,org.apache.spark:spark-token-provider-kafka-0-10_2.12:3.5.3,org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.9.1"
ENV SPARK_JARS_DIR=/opt/spark/jars
ENV IVY_CACHE_DIR=/tmp/ivy

RUN mkdir -p /opt/dc-platform/jobs /opt/dc-platform/tmp "${IVY_CACHE_DIR}" \
 && printf 'System.exit(0)\n' | /opt/spark/bin/spark-shell \
      --conf "spark.ui.enabled=false" \
      --conf "spark.jars.ivy=${IVY_CACHE_DIR}" \
      --packages "${SPARK_EXTRA_PACKAGES}" >/tmp/spark-package-resolve.log 2>&1 \
 && find "${IVY_CACHE_DIR}" -type f -name '*.jar' -exec cp -n {} "${SPARK_JARS_DIR}/" \;

COPY spark/jobs/ /opt/dc-platform/jobs/

RUN chown -R 1001:1001 /opt/dc-platform "${IVY_CACHE_DIR}"

USER 1001
