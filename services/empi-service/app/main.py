"""API HTTP del servicio EMPI (FastAPI). Entrada de comandos y lectura del Golden Record."""
from __future__ import annotations

import logging
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException

from . import service
from .db import healthy, pool
from .schemas import GoldenRecordOut, RegisterPatientRequest, RegisterPatientResponse

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool.open()
    yield
    pool.close()


app = FastAPI(title="EMPI — SanaRed (Alt. 3 Mejorada)", version="0.1.0", lifespan=lifespan)


@app.get("/health")
def health():
    """Liveness/readiness para ECS/ALB."""
    if not healthy():
        raise HTTPException(status_code=503, detail="db unavailable")
    return {"status": "ok"}


@app.post("/patients", response_model=RegisterPatientResponse, status_code=201)
def register_patient(
    req: RegisterPatientRequest,
    x_correlation_id: str | None = Header(default=None),
):
    correlation_id = _parse_corr(x_correlation_id)
    with pool.connection() as conn:
        # Todo el caso de uso corre en una transacción (append + proyección atómicos).
        result = service.register_patient(conn, req, correlation_id)
    return result


@app.get("/patients/{empi_id}", response_model=GoldenRecordOut)
def get_patient(empi_id: str):
    with pool.connection() as conn:
        gr = service.get_golden(conn, empi_id)
    if not gr:
        raise HTTPException(status_code=404, detail="empi_id not found")
    return gr


def _parse_corr(value: str | None) -> uuid.UUID:
    if not value:
        return uuid.uuid4()
    try:
        return uuid.UUID(value)
    except ValueError:
        return uuid.uuid4()
