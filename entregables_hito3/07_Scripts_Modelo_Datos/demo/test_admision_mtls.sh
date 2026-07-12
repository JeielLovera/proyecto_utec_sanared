#!/usr/bin/env bash
# =============================================================================
# test_admision_mtls.sh — Prueba el perimetro de entrada de sistemas internos
# (Modulo de Admision por sede -> ALB privado + mTLS, ver 04_..._C4_Model.md
# §Nivel 2 "Perimetro de entrada — sistemas internos" y ADR-A3M-003).
#
# El ALB interno (aws_lb.internal, alb.tf) NO es accesible desde fuera de la
# VPC: solo acepta trafico de internal_client_cidrs (10.0.0.0/8) por Direct
# Connect/VPN. Como no hay una sede on-prem real conectada, este script prueba
# el mismo camino DESDE DENTRO de la VPC: usa ECS Exec para correr el probe
# mTLS (mtls_admision_probe.py) en el contenedor 'empi', que ya vive en la
# subred privada y puede resolver/alcanzar el DNS del ALB interno.
#
# Requisitos:
#   - Stack 10-aws-empi aplicado (incluye alb_mtls_client_demo.tf: certificado
#     cliente de demo firmado por la misma CA del ALB).
#   - AWS CLI + Session Manager plugin, autenticado.
#   - Servicio ECS 'empi' con al menos una tarea RUNNING y enableExecuteCommand=true.
#
# No hace apply/destroy: solo prueba el perimetro mTLS contra la infra ya
# desplegada y deja evidencia en demo/evidencias/.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TF_10="$ROOT_DIR/infra/terraform/stacks/10-aws-empi"
DEMO_DIR="$ROOT_DIR/entregables_hito3/07_Scripts_Modelo_Datos/demo"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
EVID_DIR="$DEMO_DIR/evidencias/mtls_admision_${RUN_ID}"
mkdir -p "$EVID_DIR"

CONTAINER="empi"
REMOTE_DIR="/tmp/mtls_admision_demo"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
tf_out() { terraform -chdir="$1" output -raw "$2" 2>/dev/null || true; }

log "Leyendo outputs de Terraform (stack 10-aws-empi)..."
ALB_DNS="$(tf_out "$TF_10" internal_alb_dns)"
ECS_CLUSTER="$(tf_out "$TF_10" ecs_cluster)"
ECS_SERVICE="$(tf_out "$TF_10" ecs_service)"

for v in ALB_DNS ECS_CLUSTER ECS_SERVICE; do
  if [ -z "${!v}" ]; then
    echo "ERROR: falta el output '$v'. ¿Esta aplicado el stack 10-aws-empi?" >&2
    exit 1
  fi
done
log "ALB_DNS=$ALB_DNS | ECS_CLUSTER=$ECS_CLUSTER | ECS_SERVICE=$ECS_SERVICE"

# -----------------------------------------------------------------------------
# 1) Materializar en local el certificado cliente de demo (CA del ALB) y la CA.
# -----------------------------------------------------------------------------
log "Paso 1/6 — exportando cert cliente de demo (admision-sede-demo) y CA"
terraform -chdir="$TF_10" output -raw mtls_admision_client_cert_pem > "$EVID_DIR/client.pem"
terraform -chdir="$TF_10" output -raw mtls_admision_client_key_pem > "$EVID_DIR/client.key"
terraform -chdir="$TF_10" output -raw mtls_ca_cert_pem > "$EVID_DIR/ca.pem"

# -----------------------------------------------------------------------------
# 2) Ubicar la tarea RUNNING del servicio EMPI (el cluster tambien aloja el bus
#    self-hosted Redpanda como otro servicio; hay que filtrar por --service-name).
# -----------------------------------------------------------------------------
log "Paso 2/6 — ubicando tarea ECS del servicio $ECS_SERVICE"
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

# Corre un ecs_exec hasta 3 veces; una sesion SSM ocasionalmente no llega a
# ejecutar el comando (rate limit / latencia de negociacion) y devuelve éxito
# de todos modos si no se verifica -- eso deja archivos truncados en el
# contenedor sin que el script se entere (visto en la práctica: un chunk se
# pierde y el body del POST /patients queda corrupto -> 422 "Extra data").
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

# Sube un archivo local al contenedor en fragmentos base64 (execute-command
# tiene un limite de ~1000 caracteres por comando, insuficiente para un cert/key
# completo en una sola llamada) y verifica el tamaño resultante contra el
# original -- sin esto, un fragmento perdido deja el archivo corrupto en
# silencio (ver ecs_exec_retry).
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
  # La salida de ecs_exec trae mezclado el banner de la sesion SSM (Session
  # Manager, "Starting/Exiting session..."); hay que aislar la linea puramente
  # numerica que imprime `wc -c`, no confiar en que sea la unica salida.
  actual_size="$(ecs_exec_retry "sh -c 'wc -c < ${remote_path}'" | grep -oE '^[0-9]+$' | head -1)"
  if [ "$actual_size" != "$expected_size" ]; then
    echo "ERROR: $remote_path quedó corrupto (esperado ${expected_size} bytes, subió ${actual_size})." >&2
    return 1
  fi
}

# -----------------------------------------------------------------------------
# 3) Subir cert cliente, key, CA y el probe Python al contenedor via ECS Exec.
# -----------------------------------------------------------------------------
log "Paso 3/6 — subiendo cert/key/CA/probe al contenedor via ECS Exec (varios fragmentos, puede tardar ~1 min)"
push_file "$EVID_DIR/client.pem" "$REMOTE_DIR/client.pem"
push_file "$EVID_DIR/client.key" "$REMOTE_DIR/client.key"
push_file "$EVID_DIR/ca.pem" "$REMOTE_DIR/ca.pem"
push_file "$DEMO_DIR/mtls_admision_probe.py" "$REMOTE_DIR/probe.py"
log "OK: archivos en $REMOTE_DIR dentro del contenedor $CONTAINER"

# -----------------------------------------------------------------------------
# 4) Correr el probe: POST /patients contra el ALB privado, presentando el
#    certificado cliente de Admision (simula el registro que hace el
#    admisionista por sede, ver 04_..._C4_Model.md Nivel 1).
# -----------------------------------------------------------------------------
log "Paso 4/6 — health check mTLS contra el ALB privado ($ALB_DNS)"
ecs_exec "python3 ${REMOTE_DIR}/probe.py ${REMOTE_DIR}/client.pem ${REMOTE_DIR}/client.key ${REMOTE_DIR}/ca.pem ${ALB_DNS} /health GET" \
  | tee "$EVID_DIR/01_health_mtls.log"

# source_system=HCE: el Modulo de Admision opera sobre el HCE (ver C1 del C4
# Model), no es un sistema fuente propio en el enum SourceSystem del EMPI
# (services/empi-service/app/schemas.py) -- ese enum refleja los 6 sistemas
# existentes de SanaRed (RENIEC/HCE/LIS/PORTAL/PACS/ERP) + AGENDA.
# $1 permite pasar un payload distinto (p. ej. para encadenar con un registro
# previo por el Portal y forzar un match/merge, ver docs de demo).
# OJO: el default NO va inline en ${1:-...} -- bash no balancea las llaves { }
# literales del JSON dentro de esa expansión y deja una '}' de más pegada al
# valor final (visto en la práctica: rompía el JSON con una llave extra).
DEFAULT_BODY='{"dni":"78451236","given_name":"Carlos","family_name":"Ramirez Soto","source_system":"HCE"}'
BODY="${1:-$DEFAULT_BODY}"
log "Paso 5/6 — POST /patients (admision por sede) contra el ALB privado via mTLS"
ecs_exec "python3 ${REMOTE_DIR}/probe.py ${REMOTE_DIR}/client.pem ${REMOTE_DIR}/client.key ${REMOTE_DIR}/ca.pem ${ALB_DNS} /patients POST '${BODY}'" \
  | tee "$EVID_DIR/02_register_admision_mtls.log"

log "Paso 6/6 — limpieza de archivos temporales en el contenedor"
ecs_exec "sh -c 'rm -rf ${REMOTE_DIR}'" >/dev/null || true

cat > "$EVID_DIR/resumen.md" <<EOF
# Evidencia — perimetro mTLS de Admision (ALB privado) — corrida ${RUN_ID}

Prueba el camino ADMIS -> APIMTLS -> CORE del C4 (04_Alternativa3_Mejorada_C4_Model.md,
Nivel 2, fila "Perimetro de entrada — sistemas internos"). Como no hay una sede
on-prem real conectada por Direct Connect/VPN, se ejecuta el probe DESDE DENTRO
de la VPC (ECS Exec al contenedor \`empi\`), que es el mismo segmento de red que
usaria el trafico llegando por VPN — el ALB y su validacion mTLS son los reales.

| Paso | Archivo |
|---|---|
| Health check mTLS | 01_health_mtls.log |
| POST /patients (admision por sede) mTLS | 02_register_admision_mtls.log |
| Certificado cliente de demo (CA del ALB) | client.pem / client.key |
| CA de demo | ca.pem |

Certificado cliente: CN=admision-sede-demo.internal.sanared, firmado por la CA
de \`alb.tf\` (misma CA que valida el trust store del ALB privado,
\`aws_lb_trust_store.mtls\`) — ver \`alb_mtls_client_demo.tf\`.
EOF

log "Listo. Evidencia en: $EVID_DIR"
