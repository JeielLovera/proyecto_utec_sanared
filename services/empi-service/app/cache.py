"""Caché de identidad — ElastiCache Redis (§4.2). Paso 1 del matching: lookup exacto
por DNI antes de tocar la base. Cache-aside: hit devuelve directo; miss cae al SQL
(matcher.lookup_exact_dni) y el resultado se cachea para la próxima vez.

El DNI se hashea (SHA-256) como clave: nunca se guarda en claro en Redis (§10).
Si EMPI_REDIS_URL no está configurado, todas las funciones son no-op (permite correr
sin Redis, como hasta ahora, sin romper nada).
"""
from __future__ import annotations

from typing import Optional

import redis

from .config import settings
from .ids import dni_hash

_client: Optional[redis.Redis] = None
_TTL_SECONDS = 300  # 5 min (24h en modo degradado offline, RNF-02.3 — no implementado aquí)


def get_client() -> Optional[redis.Redis]:
    global _client
    if not settings.redis_url:
        return None
    if _client is None:
        _client = redis.Redis.from_url(settings.redis_url, decode_responses=True, socket_timeout=1.5)
    return _client


def get_dni(dni: str) -> Optional[str]:
    """Paso 1 — hit exacto. Devuelve el EMPI-ID cacheado o None (miss / sin Redis)."""
    client = get_client()
    if client is None:
        return None
    try:
        return client.get(f"empi:dni:{dni_hash(dni)}")
    except redis.RedisError:
        return None  # Redis caído no debe tumbar el alta (RNF-02: degradado)


def set_dni(dni: str, empi_id: str) -> None:
    """Puebla el caché tras un lookup SQL exitoso o un alta nueva."""
    client = get_client()
    if client is None:
        return
    try:
        client.setex(f"empi:dni:{dni_hash(dni)}", _TTL_SECONDS, empi_id)
    except redis.RedisError:
        pass
