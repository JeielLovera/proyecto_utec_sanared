# Consumidor Kafka standalone del adaptador HL7 (Azure Container Instance).
#   docker build -f services/hl7-adapter/Dockerfile -t hl7-adapter services/hl7-adapter
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
# azure-functions solo hace falta para function_app.py (demo HTTP); no se instala aquí
# porque el contenedor solo corre kafka_consumer.py (imagen más liviana).
RUN pip install --no-cache-dir confluent-kafka aws-msk-iam-sasl-signer-python \
    opentelemetry-sdk==1.27.* opentelemetry-exporter-otlp-proto-http==1.27.*

COPY hl7.py consumer_logic.py kafka_consumer.py tracing.py ./

RUN useradd -m consumer
USER consumer

CMD ["python", "kafka_consumer.py"]
