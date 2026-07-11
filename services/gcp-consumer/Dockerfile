# Consumidor GCP (Cloud Run). Build:
#   docker build -f services/gcp-consumer/Dockerfile -t gcp-consumer services/gcp-consumer
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY transform.py main.py ./

RUN useradd -m consumer
USER consumer

ENV PORT=8080
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app"]
