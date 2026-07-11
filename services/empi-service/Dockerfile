# Imagen del servicio EMPI. Construir DESDE LA RAÍZ del repo para incluir los scripts SQL
# canónicos (fuente única de verdad del esquema):
#   docker build -f services/empi-service/Dockerfile -t empi-service .
FROM python:3.12-slim

# psql para las migraciones de arranque (entrypoint).
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY services/empi-service/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Código de la app y esquema canónico (una sola fuente).
COPY services/empi-service/app ./app
COPY services/empi-service/docker-entrypoint.sh ./docker-entrypoint.sh
COPY entregables_hito3/07_Scripts_Modelo_Datos/sql ./sql
RUN chmod +x ./docker-entrypoint.sh

# Usuario no-root.
RUN useradd -m empi
USER empi

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health').status==200 else 1)"

ENTRYPOINT ["./docker-entrypoint.sh"]
