"""Pool de conexiones a PostgreSQL (RDS). El esquema del EMPI vive en `empi`."""
from __future__ import annotations

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import settings


# Todo el modelo vive en el esquema `empi` (ver 07_Scripts_Modelo_Datos/sql/). Se fija el
# search_path como opción de arranque de la conexión (no deja transacción abierta).
pool = ConnectionPool(
    conninfo=settings.database_url,
    kwargs={"row_factory": dict_row, "options": "-c search_path=empi,public"},
    min_size=1,
    max_size=5,
    open=False,
)


def healthy() -> bool:
    """Ping simple para /health (ECS/ALB)."""
    try:
        with pool.connection() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        return False
