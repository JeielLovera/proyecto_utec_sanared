"""Tracing distribuido (OpenTelemetry). Mismo patrón que
services/empi-service/app/tracing.py, replicado sin librería compartida (servicios
independientes por diseño). Sin OTEL_EXPORTER_OTLP_ENDPOINT, cae al tracer no-op.
"""
from __future__ import annotations

import os

from opentelemetry import propagate, trace
from opentelemetry.context import Context
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

SERVICE_NAME = "gcp-consumer"

_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
if _endpoint:
    _provider = TracerProvider(resource=Resource.create({"service.name": SERVICE_NAME}))
    _provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{_endpoint}/v1/traces")))
    trace.set_tracer_provider(_provider)

tracer = trace.get_tracer(SERVICE_NAME)


def extract_kafka_context(headers: list[tuple[str, bytes]] | None) -> Context:
    """Contexto de traza desde los headers del mensaje Kafka consumido (publicados
    por empi-service, ver services/empi-service/app/tracing.py:inject_kafka_headers)."""
    carrier = {k: v.decode("utf-8") for k, v in (headers or [])}
    return propagate.extract(carrier)
