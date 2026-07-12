# Guía de Despliegue — EMPI Alt. 3 Mejorada (multinube)

Cómo llevar el IaC + servicios a la nube **real**. Pensada para **cuentas de laboratorio**
(AWS Academy Learner Lab, Azure for Students, GCP free trial) con notas de sus límites.

> **Regla de oro:** aplica por **ventanas** y haz **`terraform destroy` al terminar**. Los
> recursos “siempre encendidos” (NAT, OpenSearch, MSK, VPN Gateway, APIM) consumen crédito
> aunque no los uses.

---

## 0. Herramientas (una vez)

```powershell
winget install HashiCorp.Terraform
winget install Amazon.AWSCLI
winget install Microsoft.AzureCLI
winget install Google.CloudSDK
# Docker Desktop ya está instalado en este equipo.
```

---

## 1. ¿Qué desplegar? Dos perfiles

El IaC describe la arquitectura **completa** (as-is). Para labs conviene un **perfil mínimo**
que corre **Flujo A** barato, sin las piezas caras. Se controla con toggles (ver §7):

| Pieza | ¿Necesaria para Flujo A? | Costo/lab | Toggle sugerido en lab |
|---|---|---|---|
| VPC, RDS, Redis | **Sí** (RDS sí; Redis opcional) | bajo | on |
| ECS + ECR + ALB/API GW + WAF | **Sí** | bajo | on |
| OpenSearch | No (el servicio usa `pg_trgm`) | medio | **off** en lab |
| MSK (bus) | No (servicio usa `bus_backend=noop`) | medio-alto | **off** en lab |
| VPN cross-cloud, Azure, GCP | Solo golden path B2 | alto | fase aparte |

> Con OpenSearch/MSK **off**, el stack AWS despliega barato y **Flujo A funciona igual**
> (mismo servicio, mismos eventos). Es un *perfil de despliegue*, no un recorte de la solución.

---

## 2. AWS — credenciales

**Learner Lab (AWS Academy):** abre el lab → *AWS Details* → copia el bloque `aws_access_key_id`,
`aws_secret_access_key` y `aws_session_token` a `~/.aws/credentials` (perfil `default`).
Región **us-east-1**. Las credenciales **caducan (~4 h)**: si un `apply` largo falla por token
expirado, vuelve a copiarlas y re-ejecuta `apply` (Terraform continúa donde quedó).

```powershell
aws sts get-caller-identity   # verifica que estás autenticado
```

---

## 3. AWS — orden de despliegue

### 3.1 Backend de estado (una vez). Estado local -> crea S3 + DynamoDB.
```bash
cd infra/terraform/bootstrap
terraform init && terraform apply
#   Anota el output: state_bucket (sanared-empi-tfstate-<ACCOUNT_ID>)
```

### 3.2 Núcleo EMPI
```bash
cd ../stacks/10-aws-empi
cp backend.hcl.example backend.hcl            # pega el bucket del paso 3.1
cp terraform.tfvars.example terraform.tfvars  # ajusta (ver perfil lab en §7)
terraform init -backend-config=backend.hcl
terraform plan          # revisa el número de recursos y costo
terraform apply         # ~15-25 min (RDS/OpenSearch tardan)
```

### 3.3 Construir y subir la imagen del servicio

El servicio corre desde ECR. Tras el `apply`, sube la imagen y fuerza el despliegue:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=$(terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw ecr_repository_url)

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Build DESDE LA RAÍZ del repo (incluye los sql/ canónicos)
docker build -f services/empi-service/Dockerfile -t "$REPO:latest" .
docker push "$REPO:latest"

# Forzar a ECS a tomar la imagen recién subida
aws ecs update-service --cluster sanared-empi-demo-cluster \
  --service sanared-empi-demo-empi --force-new-deployment --region $REGION
```

> Al arrancar, el contenedor aplica el esquema (`EMPI_MIGRATE=true`) sobre RDS desde dentro
> de la VPC. En 1-2 min el servicio queda *healthy* tras el ALB/API GW.

### 3.4 Verificar Flujo A en la nube

```bash
API=$(terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw patient_api_url)
curl "$API/health"
curl -X POST "$API/patients" -H 'content-type: application/json' \
  -d '{"dni":"45678999","given_name":"Rosa","family_name":"Mendoza Cruz","source_system":"PORTAL"}'
```

---

## 4. Azure (Fase 2) — credenciales y notas de lab

```powershell
az login                       # Azure for Students: usa tu cuenta del lab
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
```

**Ojo con el crédito (Azure for Students, ~US$100):** los recursos caros/lentos son
**VPN Gateway** (`VpnGw1` ~US$140/mes, ~30-45 min de provisión), **APIM Developer**
(~US$50/mes, ~30-45 min) y **Functions Premium** (EP1). Recomendado en lab:
- `enable_apim = false` (evita 45 min + US$50).
- Aplica en una **ventana corta** y `destroy` el mismo día.

```bash
cd infra/terraform/stacks/20-azure-integ
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl && terraform apply
```

---

## 5. GCP (Fase 3) — credenciales y notas de lab

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project TU-PROYECTO-GCP
```

**GCP free trial (~US$300, el más holgado de los tres):** habilita las APIs la primera vez
(Terraform las activa vía `google_project_service`, pero puede tardar unos minutos en
propagar). Si usas un **sandbox de Qwiklabs/temporal, no sirve** (proyecto efímero, APIs
restringidas) — necesitas un proyecto GCP persistente.

```bash
cd infra/terraform/stacks/30-gcp-analytics
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
#   edita project_id = "TU-PROYECTO-GCP"
terraform init -backend-config=backend.hcl && terraform apply
```

### 5.1 Construir y subir el consumidor GCP

```bash
REPO=$(terraform -chdir=infra/terraform/stacks/30-gcp-analytics output -raw artifact_registry_repo)
gcloud auth configure-docker "${REPO%%/*}"
docker build -f services/gcp-consumer/Dockerfile -t "$REPO/consumer:latest" services/gcp-consumer
docker push "$REPO/consumer:latest"
# luego: terraform apply -var="consumer_image=$REPO/consumer:latest"
```

---

## 6. VPN cross-cloud (Fase 2/3) — `40-xcloud-net`

Requiere 10, 20 y 30 ya aplicados (lee su estado). El VPN Gateway de Azure tarda ~30-45 min;
el túnel GCP (Classic VPN, sin BGP) es más rápido (~5-10 min).

```bash
cd infra/terraform/stacks/40-xcloud-net
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
#   edita state_bucket = "sanared-empi-tfstate-<ACCOUNT_ID>" y gcp_project_id
terraform init -backend-config=backend.hcl && terraform apply
```

> Este stack levanta **dos túneles independientes** desde el mismo VPN Gateway de AWS:
> uno a Azure (RouteBased/BGP-capable pero sin BGP habilitado) y otro a GCP (Classic VPN,
> también estático). Puedes aplicar solo el tramo que necesites comentando temporalmente
> los recursos del otro (`vpn.tf` = Azure, `vpn_gcp.tf` = GCP) si quieres ahorrar tiempo/costo.

---

## 6.1 Activar el golden path cross-cloud REAL (bus Kafka + consumidores)

Por defecto el servicio EMPI publica en modo `noop` (solo log) y los consumidores Azure/GCP
no están activos. Para que el `POST /patients` dispare de verdad `ADT^A40` en Azure y el
re-tag DICOM + fila `patient_360` en GCP, sigue este orden (requiere 10, 20, 30 y 40 ya
aplicados con `enable_msk = true`).

> **AWS Academy Learner Lab: MSK Serverless está bloqueado** (`kafka:CreateClusterV2`
> devuelve `AccessDenied`) — el mismo tipo de restricción que IAM y OpenSearch. Usa
> `use_self_hosted_kafka = true` en `10-aws-empi` (Redpanda en ECS Fargate, mismo
> protocolo Kafka, broker reemplazable por diseño — ADR-A3M-008). **Con este modo NO
> necesitas usuario IAM ni credenciales temporales**: el perímetro lo da el security
> group + la VPN, y `kafka_auth_mode` sale como `plaintext`. Salta directo al paso 2
> con `aws_access_key_id`/`aws_secret_access_key`/`aws_session_token` en blanco.
>
> Si en cambio tu cuenta SÍ puede crear MSK (`use_self_hosted_kafka=false`,
> `kafka_auth_mode=iam`) y además `create_iam_roles=false`, usa las **credenciales
> temporales de tu sesión** en el paso 2:
> ```bash
> cat ~/.aws/credentials   # o el panel "AWS Details" del lab
> ```
> Copia `aws_access_key_id`, `aws_secret_access_key` **y** `aws_session_token`.
> **Caducan cada ~4h** — cuando expiren, el consumidor empezará a fallar la auth;
> renuévalas con `terraform apply` de nuevo y reinicia el ACI (`az container restart`,
> paso 4) o despliega una nueva revisión de Cloud Run.

```bash
# 1) Saca el bootstrap y modo de auth del bus
terraform -chdir=infra/terraform/stacks/10-aws-empi output kafka_bootstrap
terraform -chdir=infra/terraform/stacks/10-aws-empi output kafka_auth_mode
# Si kafka_auth_mode=iam (MSK real) y create_iam_roles=true, también:
terraform -chdir=infra/terraform/stacks/10-aws-empi output kafka_xcloud_access_key_id
terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw kafka_xcloud_secret_access_key

# 2) Pégalas en terraform.tfvars de 20-azure-integ y 30-gcp-analytics
#    (kafka_bootstrap siempre; aws_access_key_id/secret/session_token SOLO si
#    kafka_auth_mode=iam) y en 20 además enable_kafka_consumer = true

# 3) Re-aplica ambos stacks (levanta el ACI del consumidor HL7 en Azure y activa el
#    hilo de fondo del consumidor en Cloud Run vía min_instance_count=1)
terraform -chdir=infra/terraform/stacks/20-azure-integ apply
terraform -chdir=infra/terraform/stacks/30-gcp-analytics apply

# 4) Sube las imágenes reales (antes corrían con placeholders)
#   Azure (ACI del consumidor HL7):
ACR=$(terraform -chdir=infra/terraform/stacks/20-azure-integ output -raw acr_login_server)
az acr login --name "${ACR%%.*}"
docker build -f services/hl7-adapter/Dockerfile -t "$ACR/hl7-adapter:latest" services/hl7-adapter
docker push "$ACR/hl7-adapter:latest"
terraform -chdir=infra/terraform/stacks/20-azure-integ apply -var="hl7_consumer_image=$ACR/hl7-adapter:latest"
#   (el cambio de imagen ya fuerza el redeploy del ACI; no hace falta "az container restart")

#   GCP (Cloud Run consumidor):
REPO=$(terraform -chdir=infra/terraform/stacks/30-gcp-analytics output -raw artifact_registry_repo)
gcloud auth configure-docker "${REPO%%/*}"
docker build -f services/gcp-consumer/Dockerfile -t "$REPO/consumer:latest" services/gcp-consumer
docker push "$REPO/consumer:latest"
terraform -chdir=infra/terraform/stacks/30-gcp-analytics apply -var="consumer_image=$REPO/consumer:latest"

# 5) Habilita el bus real en el servicio EMPI (stack 10) y redeploya
terraform -chdir=infra/terraform/stacks/10-aws-empi apply -var="enable_msk=true"
aws ecs update-service --cluster sanared-empi-demo-cluster --service sanared-empi-demo-empi \
  --force-new-deployment --region us-east-1
```

**Esto ya está verificado localmente** (sin nube real): con Redpanda + Postgres + Redis en
Docker, un `POST /patients` que produce `B2 merge` publicó de verdad en el bus, el
consumidor HL7 standalone lo leyó y entregó `ADT^A40` al HCE mock (`200 OK`), y el
consumidor GCP lo leyó y generó el plan de re-tag DICOM + la fila `patient_360` — los
tres componentes (productor, consumidor HL7, consumidor GCP) están probados; lo que
falta es la aplicación real contra AWS/Azure/GCP con tus credenciales de laboratorio.

> **Nota de seguridad (perfil demo):** la credencial cross-cloud viaja como variable de
> Terraform (`aws_access_key_id`/`aws_secret_access_key`) hacia variables de entorno
> "seguras" de ACI / Cloud Run. En producción se reemplaza por Key Vault (Azure) y Secret
> Manager (GCP) con un lector rotativo; aquí se optó por el camino directo para no sumar
> complejidad de intermediarios de secretos en el perfil de laboratorio.

---

## 6.2 Demo reproducible del golden path B2 (Fase 4)

Con 10/20/30/40 aplicados y el bus real activado (§6.1), el script
`entregables_hito3/07_Scripts_Modelo_Datos/demo/run_golden_path_b2.sh` ejecuta el flujo
end-to-end y junta la evidencia en un directorio por corrida (no hace `apply`/`destroy`):

```bash
# Requiere: aws cli, az cli, bq (gcloud), jq, terraform (para leer outputs) autenticados.
bash entregables_hito3/07_Scripts_Modelo_Datos/demo/run_golden_path_b2.sh
```

Qué hace:

1. Lee los outputs de los stacks 10/20/30 (URL de la API, ARN del secreto RDS, cluster
   ECS, resource group + nombre del ACI del HCE mock, dataset de BigQuery).
2. `POST /patients` con `payload_01_registro_survivor.json` (Flujo A, PORTAL, con DNI).
3. `POST /patients` con `payload_02_registro_duplicado_b2.json` — llega **sin DNI** desde
   HCE con el mismo apellido/nacimiento/teléfono a propósito: al no traer DNI se salta el
   Paso 1 (lookup exacto) y entra por blocking biográfico
   (`matcher.py`: `0.60·name_sim + 0.25·dob_equal + 0.15·phone_equal = 1.00 ≥ 0.95`),
   forzando el camino **B2 real** (no un `LINKED` de Paso 1). El script valida que la
   respuesta sea `decision=MERGED` contra el `survivor_empi_id` del paso 2.
4. Espera 30s a que Azure (consumidor HL7) y GCP (Cloud Run) procesen
   `identity.patient.merged` desde el bus.
5. Evidencia en RDS (`golden_record_view`, `patient_crosswalk_view`, `audit_trail`) vía
   **ECS Exec** (`aws ecs execute-command`) — corre `psql` desde dentro de la propia tarea
   ECS del servicio EMPI, sin bastión, porque RDS está en subred privada. Requiere
   `enable_execute_command = true` en el servicio ECS (ya habilitado en `ecs.tf`) y el
   permiso `ssmmessages:*Channel` en el rol de tarea (ya en `iam.tf`).
6. Evidencia cross-cloud: logs del HCE mock (Azure, busca el `ADT^A40` reflejado por el
   echo container) y la fila de `patient_360` en BigQuery (GCP).
7. Escribe `resumen.md` con el resultado de cada paso y las rutas de los archivos.

Los payloads sintéticos (`es_PE`, RNF-07) están en la misma carpeta `demo/`.

---

## 7. Perfil de laboratorio (AWS Academy Learner Lab) — YA soportado

Learner Lab **no puede** crear roles IAM (`iam:CreateRole` bloqueado) ni etiquetar/crear
OpenSearch, así que el as-is completo no aplica ahí. Usa el perfil demo con toggles:

```bash
cd infra/terraform/stacks/10-aws-empi
cp terraform.tfvars.lab.example terraform.tfvars   # ya trae los ajustes de lab
```

`terraform.tfvars.lab.example` fija:

```hcl
create_iam_roles   = false                                    # reutiliza LabRole (no crea roles)
lab_role_arn       = "arn:aws:iam::<ACCOUNT_ID>:role/LabRole" # tu cuenta
enable_opensearch  = false                                    # el servicio usa pg_trgm
enable_msk         = false                                    # el servicio usa bus_backend=noop
rds_engine_version = "16"                                     # RDS elige el minor disponible
```

Con esto el stack despliega barato y **Flujo A corre igual** (mismo servicio y eventos).
No es un recorte de la arquitectura: los defaults siguen siendo el as-is completo
(`enable_opensearch/enable_msk = true`, `create_iam_roles = true`) para cuentas sin restricción.

> **Verifica que `LabRole` confía en `ecs-tasks.amazonaws.com`** (su trust policy). En Learner
> Lab suele ser así; si ECS no arranca por "cannot assume role", ese es el motivo.

### Errores típicos de Learner Lab y su causa

| Error | Causa | Solución |
|---|---|---|
| `iam:CreateRole … AccessDenied` | Lab bloquea crear roles | `create_iam_roles=false` + `lab_role_arn` |
| `es:AddTags … AccessDenied` (OpenSearch) | Lab restringe OpenSearch | `enable_opensearch=false` |
| `Cannot find version 16.4 for postgres` | ese minor no está en la cuenta | `rds_engine_version="16"` |
| `Invalid rule description` / `WebACL description … pattern` | acentos o `<` en `description` | corregido en el IaC (ASCII) |
| `ECR Repository ... not empty` (al hacer `destroy`) | subiste una imagen (paso 3.3) y ECR no borra un repo con imágenes dentro | corregido: `force_delete = true` en `ecr.tf`. Si ya te salió el error, vacía el repo a mano (`aws ecr batch-delete-image`) y reintenta el `destroy` |
| `kafka:CreateClusterV2 ... AccessDenied` (MSK Serverless) | Lab bloquea crear clusters MSK | `use_self_hosted_kafka=true` (Redpanda en ECS Fargate, ver §6.1) |

---

## 8. Apagar todo (imprescindible en lab)

```bash
# Orden inverso al de aplicación. Destruye la VPN primero (depende de los otros 3).
terraform -chdir=infra/terraform/stacks/40-xcloud-net destroy
terraform -chdir=infra/terraform/stacks/30-gcp-analytics destroy
terraform -chdir=infra/terraform/stacks/20-azure-integ destroy
terraform -chdir=infra/terraform/stacks/10-aws-empi destroy
# El bucket de estado (bootstrap) tiene prevent_destroy: bórralo a mano si ya no lo usas.
```

---

## 9. Límites conocidos de cuentas de laboratorio

| Nube | Cuenta típica | Funciona | Riesgos / bloqueos |
|---|---|---|---|
| **AWS** | Academy Learner Lab | RDS, Redis, ECS, ALB, API GW, WAF, S3, DynamoDB | **IAM restringido** (usar `LabRole`, no crear roles); **MSK/OpenSearch/VPN pueden estar deshabilitados**; token ~4 h; región us-east-1; presupuesto ~US$50-100 |
| **Azure** | for Students | VNet, Functions, ACI, VPN GW, APIM | Crédito US$100 se agota rápido con VPN GW + APIM; provisión lenta; posibles cuotas (vCPU, IP Standard) |
| **GCP** | free trial (US$300) | Healthcare API, BigQuery, Cloud Run, Classic VPN | Amplio; sandboxes Qwiklabs sí son restringidos |
| cualquiera | **sandbox temporal** (MS Learn, Qwiklabs) | — | RG/proyecto efímero y servicios muy limitados: **no aptos** para este IaC |

---

*Guía de despliegue — Hito 3 · Complementa `08_..._Plan_Puesta_En_Escena.md` e `infra/terraform/README.md`.*
