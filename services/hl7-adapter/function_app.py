"""Adaptador HL7 (Azure Functions, modelo v2) — disparador HTTP (demo/pruebas).

El consumo Kafka REAL contra MSK Serverless (SASL/OAUTHBEARER IAM) NO usa el binding
Kafka nativo de Functions (que habla SASL PLAIN/SCRAM, incompatible con IAM): se ejecuta
como proceso standalone en `kafka_consumer.py` (confluent-kafka + aws-msk-iam-sasl-signer),
desplegado como contenedor persistente (Azure Container Instance, ver
infra/terraform/stacks/20-azure-integ/hl7_consumer.tf) en vez de la Function App.
Este módulo HTTP se mantiene para pruebas/demo manuales.
"""
from __future__ import annotations

import json

import azure.functions as func

from consumer_logic import process_event

app = func.FunctionApp()


@app.route(route="events", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def events_http(req: func.HttpRequest) -> func.HttpResponse:
    try:
        event = req.get_json()
    except ValueError:
        return func.HttpResponse("invalid json", status_code=400)
    result = process_event(event)
    return func.HttpResponse(json.dumps(result), mimetype="application/json")
