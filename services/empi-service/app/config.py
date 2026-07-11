"""Configuración por variables de entorno (prefijo EMPI_).

En AWS, ECS inyecta estos valores desde SSM Parameter Store / Secrets Manager
(ver infra/terraform/stacks/10-aws-empi/ssm.tf).
"""
from __future__ import annotations

from urllib.parse import quote

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="EMPI_", extra="ignore")

    # Conexión al Event Store + proyecciones (RDS PostgreSQL).
    # Se puede dar como URL completa, o por partes (como las inyecta ECS desde SSM/Secrets).
    database_url: str = "postgresql://postgres:empi@localhost:5432/postgres"
    db_host: str | None = None
    db_port: int = 5432
    db_name: str = "empi"
    db_user: str | None = None
    db_password: str | None = None

    # Caché de identidad (opcional; §4.2). Si es None, se omite el Paso 1 por Redis.
    redis_url: str | None = None

    # Bus de eventos: "noop" (log) por defecto; "kafka" en Fase 2/3.
    bus_backend: str = "noop"
    kafka_bootstrap: str | None = None

    # Umbrales del matcher (§5.2). En prod vienen de SSM (RNF-06.2).
    threshold_auto: float = 0.95
    threshold_review: float = 0.85
    model_version: str = "fs-2026.1"

    environment: str = "demo"

    @model_validator(mode="after")
    def _compose_url(self):
        # Si vienen las partes (ECS/SSM/Secrets), se arma el DSN.
        if self.db_host and self.db_user:
            pwd = quote(self.db_password or "", safe="")
            self.database_url = (
                f"postgresql://{self.db_user}:{pwd}@{self.db_host}:{self.db_port}/{self.db_name}"
            )
        return self


settings = Settings()
