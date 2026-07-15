#!/usr/bin/env bash
# =============================================================================
# register_admision_portal_patient.sh — Registra, vía el perímetro mTLS del
# Módulo de Admisión (ALB privado), AL MISMO paciente dado de alta por el
# Portal público (ver portal_publico_registro.postman_collection.json), sin
# dni y con source_system=HCE, para que el matcher biográfico (matcher.py)
# lo resuelva por blocking (name+dob+phone) y dispare MERGED/B2 en vez de un
# lookup exacto por DNI.
#
# Reusa el mismo camino de entrada que test_admision_mtls.sh (ECS Exec al
# contenedor 'empi', que vive en la subred privada donde SÍ resuelve el ALB
# interno) — ver ese script para el detalle de por qué (no hay sede on-prem
# real conectada por VPN/Direct Connect).
#
# Genera su propio traceparent (W3C Trace Context) y lo inyecta como header
# HTTP vía mtls_admision_probe.py: así el trace_id se conoce ANTES de mandar
# el request, sin tener que buscarlo en Jaeger/Grafana por servicio+hora.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TF_10="$ROOT_DIR/infra/terraform/stacks/10-aws-empi"
TF_50="$ROOT_DIR/infra/terraform/stacks/50-observability"
DEMO_DIR="$ROOT_DIR/entregables_hito3/07_Scripts_Modelo_Datos/demo"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
EVID_DIR="$DEMO_DIR/evidencias/admision_portal_match_${RUN_ID}"
mkdir -p "$EVID_DIR"

CONTAINER="empi"
REMOTE_DIR="/tmp/admision_portal_match"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
tf_out() { terraform -chdir="$1" output -raw "$2" 2>/dev/null || true; }

log "Leyendo outputs de Terraform..."
ALB_DNS="$(tf_out "$TF_10" internal_alb_dns)"
ECS_CLUSTER="$(tf_out "$TF_10" ecs_cluster)"
ECS_SERVICE="$(tf_out "$TF_10" ecs_service)"
JAEGER_URL="$(tf_out "$TF_50" jaeger_ui_url)"

for v in ALB_DNS ECS_CLUSTER ECS_SERVICE; do
  if [ -z "${!v}" ]; then
    echo "ERROR: falta el output '$v'. ¿Está aplicado el stack 10-aws-empi?" >&2
    exit 1
  fi
done
log "ALB_DNS=$ALB_DNS | ECS_CLUSTER=$ECS_CLUSTER | ECS_SERVICE=$ECS_SERVICE"

# -----------------------------------------------------------------------------
# 0) traceparent propio (W3C Trace Context) -- 32 hex = trace-id, 16 hex =
#    parent span-id. Con esto el trace_id se conoce de antemano.
# -----------------------------------------------------------------------------
TRACE_ID="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
SPAN_ID="$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')"
TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"
log "traceparent generado -> trace_id=${TRACE_ID}"

# -----------------------------------------------------------------------------
# 1) Materializar en local el certificado cliente de demo (CA del ALB).
# -----------------------------------------------------------------------------
log "Paso 1/5 — exportando cert cliente de demo (admision-sede-demo) y CA"
terraform -chdir="$TF_10" output -raw mtls_admision_client_cert_pem > "$EVID_DIR/client.pem"
terraform -chdir="$TF_10" output -raw mtls_admision_client_key_pem > "$EVID_DIR/client.key"
terraform -chdir="$TF_10" output -raw mtls_ca_cert_pem > "$EVID_DIR/ca.pem"

# -----------------------------------------------------------------------------
# 2) Ubicar la tarea RUNNING del servicio EMPI (el cluster también aloja el
#    bus self-hosted Redpanda como otro servicio; hay que filtrar por --service-name).
# -----------------------------------------------------------------------------
log "Paso 2/5 — ubicando tarea ECS del servicio $ECS_SERVICE"
TASK_ARN="$(aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" \
  --desired-status RUNNING --query 'taskArns[0]' --output text)"
if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
  echo "ERROR: no hay tareas RUNNING para $ECS_SERVICE en $ECS_CLUSTER." >&2
  exit 1
fi
log "TASK_ARN=$TASK_ARN"

ecs_exec() {
  aws ecs execute-command --cluster "$ECS_CLUSTER" --task "$TASK_ARN" \
    --container "$CONTAINER" --interactive --command "$1" 2>&1
}

# Corre un ecs_exec hasta 3 veces (ver test_admision_mtls.sh: una sesión SSM
# ocasionalmente no llega a ejecutar el comando y devuelve éxito igual).
ecs_exec_retry() {
  local attempt out
  for attempt in 1 2 3; do
    out="$(ecs_exec "$1")"
    if ! echo "$out" | grep -qiE "error|denied|failed"; then
      echo "$out"
      return 0
    fi
    log "  reintento $attempt/3 (salida sospechosa de ecs_exec)"
  done
  echo "$out"
  return 1
}

# Sube un archivo local al contenedor en fragmentos base64 y verifica el
# tamaño resultante (ver test_admision_mtls.sh para el detalle del porqué).
push_file() {
  local local_path="$1" remote_path="$2" chunk_size=700
  local b64 len i chunk expected_size actual_size
  b64="$(base64 -w0 "$local_path")"
  len=${#b64}
  expected_size=$(wc -c < "$local_path")
  ecs_exec_retry "sh -c 'mkdir -p ${REMOTE_DIR} && rm -f ${remote_path}.b64'" >/dev/null
  i=0
  while [ "$i" -lt "$len" ]; do
    chunk="${b64:$i:$chunk_size}"
    ecs_exec_retry "sh -c \"printf '%s' '${chunk}' >> ${remote_path}.b64\"" >/dev/null
    i=$((i + chunk_size))
  done
  ecs_exec_retry "sh -c 'base64 -d ${remote_path}.b64 > ${remote_path} && rm -f ${remote_path}.b64'" >/dev/null
  actual_size="$(ecs_exec_retry "sh -c 'wc -c < ${remote_path}'" | grep -oE '^[0-9]+$' | head -1)"
  if [ "$actual_size" != "$expected_size" ]; then
    echo "ERROR: $remote_path quedó corrupto (esperado ${expected_size} bytes, subió ${actual_size})." >&2
    return 1
  fi
}

log "Paso 3/5 — subiendo cert/key/CA/probe al contenedor via ECS Exec (puede tardar ~1 min)"
push_file "$EVID_DIR/client.pem" "$REMOTE_DIR/client.pem"
push_file "$EVID_DIR/client.key" "$REMOTE_DIR/client.key"
push_file "$EVID_DIR/ca.pem" "$REMOTE_DIR/ca.pem"
push_file "$DEMO_DIR/mtls_admision_probe.py" "$REMOTE_DIR/probe.py"
log "OK: archivos en $REMOTE_DIR dentro del contenedor $CONTAINER"

# -----------------------------------------------------------------------------
# 4) POST /patients — MISMO paciente del Portal (nombre+nacimiento+teléfono),
#    SIN dni y source_system=HCE, para que entre por blocking biográfico y
#    haga match con el registro del Portal (ver payload_02_..._b2.json).
# -----------------------------------------------------------------------------
BODY='{"given_name":"Sofía Alejandra","family_name":"Vega Chumpitaz","birth_date":"1994-05-09","gender":"female","phone":"+51977889900","source_system":"HCE","verification_status":"INCOMPLETO","identifiers":[{"type":"HIST","value":"HIST-SEDE2-64712","assigning_sede":"SEDE-2","use":"official"}]}'
log "Paso 4/5 — POST /patients (Admisión, mTLS) contra el ALB privado ($ALB_DNS)"
ecs_exec "python3 ${REMOTE_DIR}/probe.py ${REMOTE_DIR}/client.pem ${REMOTE_DIR}/client.key ${REMOTE_DIR}/ca.pem ${ALB_DNS} /patients POST '${BODY}' 'traceparent: ${TRACEPARENT}'" \
  | tee "$EVID_DIR/01_register_admision_match.log"

log "Paso 5/5 — limpieza de archivos temporales en el contenedor"
ecs_exec "sh -c 'rm -rf ${REMOTE_DIR}'" >/dev/null || true

cat > "$EVID_DIR/resumen.md" <<EOF
# Evidencia — registro del mismo paciente vía Admisión (mTLS) — corrida ${RUN_ID}

Complementa el registro hecho por el Portal público (Postman:
\`portal_publico_registro.postman_collection.json\`, paciente Sofía
Alejandra Vega Chumpitaz). Mismo given_name/family_name/birth_date/phone,
SIN dni, \`source_system=HCE\` -> debería resolver \`decision=MERGED\`
contra el \`empi_id\` creado por el Portal.

| Campo | Valor |
|---|---|
| trace_id | ${TRACE_ID} |
| traceparent enviado | ${TRACEPARENT} |
| Trace en Jaeger | ${JAEGER_URL}/trace/${TRACE_ID} |

Archivo con la respuesta: 01_register_admision_match.log
EOF

log "Listo. trace_id=${TRACE_ID}"
[ -n "$JAEGER_URL" ] && log "Ábrelo directo en Jaeger -> ${JAEGER_URL}/trace/${TRACE_ID}"
log "Evidencia en: $EVID_DIR"
