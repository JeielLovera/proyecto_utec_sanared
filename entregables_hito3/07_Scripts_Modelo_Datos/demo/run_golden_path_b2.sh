#!/usr/bin/env bash
# =============================================================================
# run_golden_path_b2.sh — Demo reproducible del golden path B2 (Fase 4, ver
# entregables_hito3/08_Alternativa3_Mejorada_Plan_Puesta_En_Escena.md §5-6-7).
#
# Ejecuta el Flujo B2 (merge automático cross-cloud) contra la infraestructura
# REAL ya desplegada (stacks 10-aws-empi, 20-azure-integ, 30-gcp-analytics,
# 40-xcloud-net con el bus activado, ver DEPLOYMENT.md §6.1) y junta la evidencia
# en un directorio versionado por corrida.
#
# Requisitos antes de correr esto:
#   - 10/20/30/40 aplicados y el bus real activado (DEPLOYMENT.md §6.1).
#   - AWS CLI, Azure CLI, bq (gcloud) y jq disponibles y autenticados.
#   - Terraform con acceso a los 3 estados remotos (para leer outputs).
#
# No hace `apply`/`destroy`: solo ejecuta el flujo y recolecta evidencia.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TF_10="$ROOT_DIR/infra/terraform/stacks/10-aws-empi"
TF_20="$ROOT_DIR/infra/terraform/stacks/20-azure-integ"
TF_30="$ROOT_DIR/infra/terraform/stacks/30-gcp-analytics"
DEMO_DIR="$ROOT_DIR/entregables_hito3/07_Scripts_Modelo_Datos/demo"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
EVID_DIR="$DEMO_DIR/evidencias/run_${RUN_ID}"
mkdir -p "$EVID_DIR"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

tf_out() { terraform -chdir="$1" output -raw "$2" 2>/dev/null || true; }

log "Leyendo outputs de Terraform (stacks 10/20/30)..."
API_URL="$(tf_out "$TF_10" patient_api_url)"
RDS_SECRET_ARN="$(tf_out "$TF_10" rds_secret_arn)"
RDS_ENDPOINT="$(tf_out "$TF_10" rds_endpoint)"
ECS_CLUSTER="$(tf_out "$TF_10" ecs_cluster)"
ECS_SERVICE="$(tf_out "$TF_10" ecs_service)"
RG_NAME="$(tf_out "$TF_20" resource_group_name)"
HCE_CONTAINER="$(tf_out "$TF_20" hce_mock_container_name)"
BQ_DATASET="$(tf_out "$TF_30" bigquery_dataset)"
BQ_PROJECT="$(tf_out "$TF_30" project_id)"

for v in API_URL RDS_SECRET_ARN ECS_CLUSTER ECS_SERVICE RG_NAME HCE_CONTAINER BQ_DATASET BQ_PROJECT; do
  if [ -z "${!v}" ]; then
    echo "ERROR: falta el output '$v'. ¿Están aplicados los stacks 10/20/30 y el bus activado (DEPLOYMENT.md §6.1)?" >&2
    exit 1
  fi
done
log "API_URL=$API_URL | ECS_CLUSTER=$ECS_CLUSTER | ECS_SERVICE=$ECS_SERVICE | RG_NAME=$RG_NAME | BQ=$BQ_PROJECT.$BQ_DATASET"

# -----------------------------------------------------------------------------
# 1) Alta del paciente survivor (Flujo A, PORTAL, con DNI) — dispara REGISTERED.
# -----------------------------------------------------------------------------
log "Paso 1/6 — POST /patients (survivor, Flujo A)"
curl -sS -X POST "$API_URL/patients" -H 'content-type: application/json' \
  -H "x-correlation-id: $(uuidgen 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())')" \
  -d @"$DEMO_DIR/payload_01_registro_survivor.json" \
  | tee "$EVID_DIR/01_register_survivor.json"

SURVIVOR_ID="$(jq -r '.empi_id' "$EVID_DIR/01_register_survivor.json")"
log "survivor_empi_id=$SURVIVOR_ID"

# -----------------------------------------------------------------------------
# 2) Alta del registro entrante SIN DNI (HCE) — mismo apellido+nacimiento+teléfono.
#    Al no traer DNI se salta el Paso 1 (lookup exacto) y entra por blocking
#    biográfico (matcher.py: name_sim=1.0*0.60 + dob_equal*0.25 + phone_equal*0.15
#    = 1.00 >= threshold_auto 0.95) -> AUTO_MERGE (B2), NO un simple LINKED.
# -----------------------------------------------------------------------------
log "Paso 2/6 — POST /patients (entrante HCE sin DNI -> debe resolver MERGED/B2)"
curl -sS -X POST "$API_URL/patients" -H 'content-type: application/json' \
  -d @"$DEMO_DIR/payload_02_registro_duplicado_b2.json" \
  | tee "$EVID_DIR/02_register_duplicate_merge.json"

DECISION="$(jq -r '.decision' "$EVID_DIR/02_register_duplicate_merge.json")"
MERGED_SURVIVOR="$(jq -r '.survivor_empi_id' "$EVID_DIR/02_register_duplicate_merge.json")"
if [ "$DECISION" != "MERGED" ] || [ "$MERGED_SURVIVOR" != "$SURVIVOR_ID" ]; then
  echo "ERROR: se esperaba decision=MERGED con survivor_empi_id=$SURVIVOR_ID, se obtuvo decision=$DECISION survivor=$MERGED_SURVIVOR" >&2
  exit 1
fi
log "OK: B2 resuelto -> decision=MERGED, survivor=$SURVIVOR_ID"

# -----------------------------------------------------------------------------
# 3) Golden record del survivor vía API (proyección ya consolidada).
# -----------------------------------------------------------------------------
log "Paso 3/6 — GET /patients/{survivor}"
curl -sS "$API_URL/patients/$SURVIVOR_ID" | tee "$EVID_DIR/03_golden_record_api.json" >/dev/null

# -----------------------------------------------------------------------------
# 4) Esperar a que los consumidores cross-cloud (Azure/GCP) procesen el evento
#    identity.patient.merged publicado en el bus.
# -----------------------------------------------------------------------------
log "Paso 4/6 — esperando 30s a los consumidores cross-cloud (Azure ADT^A40, GCP re-tag+360)"
sleep 30

# -----------------------------------------------------------------------------
# 5) Evidencia en RDS (golden_record_view, patient_crosswalk_view, audit_trail)
#    vía ECS Exec: RDS está en subred privada, se corre psql DESDE la propia tarea
#    ECS del servicio EMPI (requiere enable_execute_command=true, ver ecs.tf).
#    El cluster también aloja el bus self-hosted (Redpanda) como otro servicio,
#    así que hay que filtrar por --service-name; de lo contrario list-tasks puede
#    devolver la tarea de Redpanda (sin ECS Exec habilitado ni contenedor "empi").
# -----------------------------------------------------------------------------
log "Paso 5/6 — evidencia RDS vía ECS Exec (golden_record_view/crosswalk/audit_trail)"
TASK_ARN="$(aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name "$ECS_SERVICE" --desired-status RUNNING --query 'taskArns[0]' --output text)"
if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
  echo "ADVERTENCIA: no se encontró una tarea ECS corriendo en $ECS_CLUSTER; se omite la evidencia RDS." >&2
else
  DSN_JSON="$(aws secretsmanager get-secret-value --secret-id "$RDS_SECRET_ARN" --query SecretString --output text)"
  DB_USER="$(echo "$DSN_JSON" | jq -r '.username')"
  DB_PASS="$(echo "$DSN_JSON" | jq -r '.password')"
  SQL="SELECT * FROM empi.golden_record_view WHERE empi_id IN ('$SURVIVOR_ID') OR empi_id_activo = '$SURVIVOR_ID'; \
       SELECT * FROM empi.patient_crosswalk_view WHERE active_empi_id = '$SURVIVOR_ID' ORDER BY identifier_type; \
       SELECT * FROM empi.audit_trail WHERE empi_id = '$SURVIVOR_ID' OR causation_id IS NOT NULL ORDER BY occurred_at;"
  aws ecs execute-command --cluster "$ECS_CLUSTER" --task "$TASK_ARN" --container empi --interactive \
    --command "psql \"postgresql://${DB_USER}:${DB_PASS}@${RDS_ENDPOINT}:5432/empi\" -c \"$SQL\"" \
    > "$EVID_DIR/05_evidencia_rds.txt" 2>&1 || log "ADVERTENCIA: ECS Exec falló; revisa $EVID_DIR/05_evidencia_rds.txt"
fi

# -----------------------------------------------------------------------------
# 6) Evidencia cross-cloud: ADT^A40 en el HCE mock (Azure) + fila patient_360 (GCP).
# -----------------------------------------------------------------------------
log "Paso 6/6 — evidencia Azure (ADT^A40) + GCP (patient_360)"
az container logs --resource-group "$RG_NAME" --name "$HCE_CONTAINER" \
  > "$EVID_DIR/06_hce_mock_adt_a40.log" 2>&1 || log "ADVERTENCIA: no se pudieron leer logs del HCE mock"

bq query --project_id="$BQ_PROJECT" --use_legacy_sql=false --format=prettyjson \
  "SELECT * FROM \`${BQ_PROJECT}.${BQ_DATASET}.patient_360\` WHERE empi_id = '${SURVIVOR_ID}'" \
  > "$EVID_DIR/07_patient_360.json" 2>&1 || log "ADVERTENCIA: no se pudo consultar BigQuery"

# -----------------------------------------------------------------------------
# Resumen
# -----------------------------------------------------------------------------
cat > "$EVID_DIR/resumen.md" <<EOF
# Evidencia golden path B2 — corrida ${RUN_ID}

| Paso | Resultado | Archivo |
|---|---|---|
| 1. Alta survivor (Flujo A) | empi_id=${SURVIVOR_ID} | 01_register_survivor.json |
| 2. Alta entrante sin DNI -> B2 | decision=${DECISION}, survivor=${MERGED_SURVIVOR} | 02_register_duplicate_merge.json |
| 3. Golden record (API) | — | 03_golden_record_api.json |
| 4. Espera consumidores cross-cloud | 30s | — |
| 5. RDS: golden_record_view/crosswalk/audit_trail | — | 05_evidencia_rds.txt |
| 6. Azure: ADT^A40 (HCE mock, echo) | — | 06_hce_mock_adt_a40.log |
| 7. GCP: fila patient_360 | — | 07_patient_360.json |

Trazabilidad: doc 08 §5 (golden path B2), doc 06 §4-6 (flujo), doc 07 §3.7/§7 (audit_trail/patient_360).
EOF

log "Listo. Evidencia en: $EVID_DIR"
