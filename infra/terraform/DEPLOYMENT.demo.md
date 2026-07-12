# Puesta en escena — Perfil DEMO (cuentas de laboratorio)

Pasos y comandos para levantar el EMPI completo (Flujo A + bus real + golden path B2
cross-cloud) contra **AWS Academy Learner Lab + Azure for Students + GCP free trial**.
Es exactamente la secuencia con la que se validó el golden path B2 en la nube real.

Todos los comandos se corren **desde la raíz del repo** (usan `terraform -chdir=...`).

`terraform destroy` al terminar la sesión (§9) — el estado remoto permite recrear igual.

---

## 0. Herramientas

```powershell
winget install HashiCorp.Terraform
winget install Amazon.AWSCLI
winget install Microsoft.AzureCLI
winget install Google.CloudSDK
winget install jqlang.jq
winget install Amazon.SessionManagerPlugin   # requerido por ECS Exec (evidencia RDS, §8)
```

## 1. Credenciales

```bash
# AWS Academy Learner Lab -> panel "AWS Details" -> pega en ~/.aws/credentials (perfil default)
aws sts get-caller-identity

az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

gcloud auth login
gcloud auth application-default login
gcloud config set project TU-PROYECTO-GCP
```

> Las credenciales de AWS Academy caducan (~4h). Si un comando falla por token expirado,
> vuelve a pegarlas y repite el comando — Terraform continúa donde quedó.

---

## 2. Backend de estado (una vez)

```bash
terraform -chdir=infra/terraform/bootstrap init
terraform -chdir=infra/terraform/bootstrap apply
# anota el output: state_bucket (sanared-empi-tfstate-<ACCOUNT_ID>)
```

---

## 3. AWS — núcleo EMPI (`10-aws-empi`)

```bash
cp infra/terraform/stacks/10-aws-empi/backend.hcl.example infra/terraform/stacks/10-aws-empi/backend.hcl
cp infra/terraform/stacks/10-aws-empi/terraform.tfvars.lab.example infra/terraform/stacks/10-aws-empi/terraform.tfvars
```

Edita `infra/terraform/stacks/10-aws-empi/terraform.tfvars`:
- pega el `state_bucket` del paso 2 en `backend.hcl`
- reemplaza `lab_role_arn` con tu `ACCOUNT_ID` (`arn:aws:iam::<ACCOUNT_ID>:role/LabRole`)

```bash
terraform -chdir=infra/terraform/stacks/10-aws-empi init -backend-config=backend.hcl
terraform -chdir=infra/terraform/stacks/10-aws-empi apply
```

### 3.1 Construir y subir la imagen del servicio

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=$(terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw ecr_repository_url)

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Build DESDE LA RAÍZ del repo (incluye los sql/ canónicos)
docker build -f services/empi-service/Dockerfile -t "$REPO:latest" .
docker push "$REPO:latest"

aws ecs update-service --cluster sanared-empi-demo-cluster \
  --service sanared-empi-demo-empi --force-new-deployment --region "$REGION"
```

### 3.2 Verificar Flujo A

```bash
API=$(terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw patient_api_url)
curl "$API/health"
curl -X POST "$API/patients" -H 'content-type: application/json' \
  -d '{"dni":"45678999","given_name":"Rosa","family_name":"Mendoza Cruz","source_system":"PORTAL"}'
```

---

## 4. Azure — integración (`20-azure-integ`)

```bash
cp infra/terraform/stacks/20-azure-integ/backend.hcl.example infra/terraform/stacks/20-azure-integ/backend.hcl
cp infra/terraform/stacks/20-azure-integ/terraform.tfvars.example infra/terraform/stacks/20-azure-integ/terraform.tfvars
```

Edita `infra/terraform/stacks/20-azure-integ/terraform.tfvars`:

```hcl
subscription_id = "TU_SUBSCRIPTION_ID"
enable_apim     = false   # evita ~30-45 min + costo; el egress a HCE va directo al mock ACI

create_resource_group        = false
existing_resource_group_name = "TU_RESOURCE_GROUP"   # el que te asignó el lab

enable_function_app = false   # la Function App es solo el disparador HTTP de demo
```

```bash
terraform -chdir=infra/terraform/stacks/20-azure-integ init -backend-config=backend.hcl
terraform -chdir=infra/terraform/stacks/20-azure-integ apply
```

---

## 5. GCP — analítica (`30-gcp-analytics`)

```bash
cp infra/terraform/stacks/30-gcp-analytics/backend.hcl.example infra/terraform/stacks/30-gcp-analytics/backend.hcl
cp infra/terraform/stacks/30-gcp-analytics/terraform.tfvars.example infra/terraform/stacks/30-gcp-analytics/terraform.tfvars
```

Edita `infra/terraform/stacks/30-gcp-analytics/terraform.tfvars`: `project_id = "TU-PROYECTO-GCP"`.

```bash
terraform -chdir=infra/terraform/stacks/30-gcp-analytics init -backend-config=backend.hcl
terraform -chdir=infra/terraform/stacks/30-gcp-analytics apply
```

### 5.1 Construir y subir el consumidor GCP

```bash
REPO=$(terraform -chdir=infra/terraform/stacks/30-gcp-analytics output -raw artifact_registry_repo)
gcloud auth configure-docker "${REPO%%/*}"
docker build -f services/gcp-consumer/Dockerfile -t "$REPO/consumer:latest" services/gcp-consumer
docker push "$REPO/consumer:latest"
terraform -chdir=infra/terraform/stacks/30-gcp-analytics apply -var="consumer_image=$REPO/consumer:latest"
```

---

## 6. VPN cross-cloud (`40-xcloud-net`)

```bash
cp infra/terraform/stacks/40-xcloud-net/backend.hcl.example infra/terraform/stacks/40-xcloud-net/backend.hcl
cp infra/terraform/stacks/40-xcloud-net/terraform.tfvars.example infra/terraform/stacks/40-xcloud-net/terraform.tfvars
```

Edita `infra/terraform/stacks/40-xcloud-net/terraform.tfvars`:

```hcl
state_bucket   = "sanared-empi-tfstate-<ACCOUNT_ID>"
shared_key     = "TU-PSK-8-64-chars"
gcp_project_id = "TU-PROYECTO-GCP"
shared_key_gcp = "TU-PSK-8-64-chars"
```

```bash
terraform -chdir=infra/terraform/stacks/40-xcloud-net init -backend-config=backend.hcl
terraform -chdir=infra/terraform/stacks/40-xcloud-net apply
```

---

## 7. Activar el golden path B2 (bus real + consumidores)

AWS Academy Learner Lab bloquea MSK Serverless; el bus real self-hosted (Redpanda,
`use_self_hosted_kafka=true`) ya quedó activo desde el paso 3 — `kafka_auth_mode=plaintext`,
sin credencial IAM.

```bash
# 1) Bootstrap del bus
terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw kafka_bootstrap
```

Edita `infra/terraform/stacks/20-azure-integ/terraform.tfvars` y
`infra/terraform/stacks/30-gcp-analytics/terraform.tfvars`, agregando:

```hcl
kafka_bootstrap = "<el bootstrap del paso anterior>"
kafka_auth_mode = "plaintext"
```

Y en `20-azure-integ/terraform.tfvars` además: `enable_kafka_consumer = true`.

```bash
# 2) Re-aplica ambos stacks (activa el consumidor HL7 en Azure y en Cloud Run)
terraform -chdir=infra/terraform/stacks/20-azure-integ apply
terraform -chdir=infra/terraform/stacks/30-gcp-analytics apply

# 3) Sube la imagen real del adaptador HL7 (Azure)
ACR=$(terraform -chdir=infra/terraform/stacks/20-azure-integ output -raw acr_login_server)
az acr login --name "${ACR%%.*}"
docker build -f services/hl7-adapter/Dockerfile -t "$ACR/hl7-adapter:latest" services/hl7-adapter
docker push "$ACR/hl7-adapter:latest"
terraform -chdir=infra/terraform/stacks/20-azure-integ apply -var="hl7_consumer_image=$ACR/hl7-adapter:latest"
```

---

## 8. Ejecutar el golden path B2 y recolectar evidencia

```bash
bash entregables_hito3/07_Scripts_Modelo_Datos/demo/run_golden_path_b2.sh
```

Registra un survivor (Flujo A), registra un entrante sin DNI que dispara `MERGED` (B2),
y junta evidencia real (RDS vía ECS Exec, `ADT^A40` en el HCE mock de Azure, fila
`patient_360` en BigQuery) en `entregables_hito3/07_Scripts_Modelo_Datos/demo/evidencias/`.

Para probarlo manualmente (Postman): importa
`entregables_hito3/07_Scripts_Modelo_Datos/demo/postman_collection.json` y corre las
3 requests en orden.

---

## 9. Apagar todo

```bash
terraform -chdir=infra/terraform/stacks/40-xcloud-net destroy
terraform -chdir=infra/terraform/stacks/30-gcp-analytics destroy
terraform -chdir=infra/terraform/stacks/20-azure-integ destroy
terraform -chdir=infra/terraform/stacks/10-aws-empi destroy
```

El bucket de estado (`bootstrap`) tiene `prevent_destroy`: bórralo a mano solo si ya no
vas a reusar la topología.

---

*Perfil DEMO · Complementa `DEPLOYMENT.prod.md` (cuentas full) y `08_..._Plan_Puesta_En_Escena.md`.*
