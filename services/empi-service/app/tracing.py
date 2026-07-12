"""Tracing distribuido (OpenTelemetry, exportado por OTLP/HTTP al stack
infra/terraform/stacks/50-observability/, Jaeger+Grafana).

Sin OTEL_EXPORTER_OTLP_ENDPOINT configurado, el SDK no se inicializa: la API de
OTel cae a su TracerProvider no-op por defecto, así que instrumentar es seguro
incluso sin el stack de observabilidad desplegado (perfiles donde no aplica).
"""
from __future__ import annotations

import os

from opentelemetry import propagate, trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

SERVICE_NAME = "empi-core"

_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
if _endpoint:
    _provider = TracerProvider(resource=Resource.create({"service.name": SERVICE_NAME}))
    _provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{_endpoint}/v1/traces")))
    trace.set_tracer_provider(_provider)

tracer = trace.get_tracer(SERVICE_NAME)


def inject_kafka_headers() -> list[tuple[str, bytes]]:
    """Contexto de traza actual (del request HTTP en curso) como headers Kafka
    (confluent-kafka espera list[(str, bytes)]), para que el consumidor cross-cloud
    (hl7-adapter / gcp-consumer) continúe la misma traza."""
    carrier: dict[str, str] = {}
    propagate.inject(carrier)
    return [(k, v.encode("utf-8")) for k, v in carrier.items()]
