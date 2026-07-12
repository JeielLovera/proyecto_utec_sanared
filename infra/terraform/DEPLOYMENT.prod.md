# Puesta en escena — Perfil PROD (cuentas full, as-is completo)

Pasos y comandos para levantar el EMPI completo con los defaults as-is (sin toggles de
laboratorio): MSK Serverless gestionado, OpenSearch, APIM, Function App, roles IAM
propios y usuario IAM cross-cloud dedicado. Requiere cuentas AWS/Azure/GCP sin las
restricciones de una cuenta académica.

Todos los comandos se corren **desde la raíz del repo** (usan `terraform -chdir=...`).

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
aws configure                    # perfil dedicado, no una sesión temporal
aws sts get-caller-identity

az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

gcloud auth login
gcloud auth application-default login
gcloud config set project TU-PROYECTO-GCP
```

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
cp infra/terraform/stacks/10-aws-empi/terraform.tfvars.example infra/terraform/stacks/10-aws-empi/terraform.tfvars
```

Edita `infra/terraform/stacks/10-aws-empi/terraform.tfvars`: `environment = "prod"`, pega
el `state_bucket` del paso 2 en `backend.hcl`, ajusta `aws_region`/`vpc_cidr` si hace
falta. No agregues ningún toggle de lab (`create_iam_roles`, `enable_opensearch`,
`enable_msk`, `use_self_hosted_kafka` quedan en sus defaults as-is: `true, true, true, false`).

```bash
terraform -chdir=infra/terraform/stacks/10-aws-empi init -backend-config=backend.hcl
terraform -chdir=infra/terraform/stacks/10-aws-empi apply       # ~20-30 min (RDS multi-AZ + OpenSearch tardan)
```

### 3.1 Construir y subir la imagen del servicio

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)   # el aws_region que pusiste en terraform.tfvars
REPO=$(terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw ecr_repository_url)

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

docker build -f services/empi-service/Dockerfile -t "$REPO:latest" .
docker push "$REPO:latest"

aws ecs update-service --cluster sanared-empi-prod-cluster \
  --service sanared-empi-prod-empi --force-new-deployment --region "$REGION"
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

Edita `infra/terraform/stacks/20-azure-integ/terraform.tfvars`: `environment = "prod"`,
`subscription_id = "TU_SUBSCRIPTION_ID"`. Deja `enable_apim = true` y
`enable_function_app = true` (defaults as-is).

```bash
terraform -chdir=infra/terraform/stacks/20-azure-integ init -backend-config=backend.hcl
terraform -chdir=infra/terraform/stacks/20-azure-integ apply       # ~40-60 min (APIM + VPN Gateway son los recursos lentos)
```

---

## 5. GCP — analítica (`30-gcp-analytics`)

```bash
cp infra/terraform/stacks/30-gcp-analytics/backend.hcl.example infra/terraform/stacks/30-gcp-analytics/backend.hcl
cp infra/terraform/stacks/30-gcp-analytics/terraform.tfvars.example infra/terraform/stacks/30-gcp-analytics/terraform.tfvars
```

Edita `infra/terraform/stacks/30-gcp-analytics/terraform.tfvars`: `environment = "prod"`,
`project_id = "TU-PROYECTO-GCP"`.

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
environment    = "prod"
state_bucket   = "sanared-empi-tfstate-<ACCOUNT_ID>"
shared_key     = "PSK-propio-8-64-chars-no-committear"
gcp_project_id = "TU-PROYECTO-GCP"
shared_key_gcp = "otro-PSK-propio-8-64-chars"
```

```bash
terraform -chdir=infra/terraform/stacks/40-xcloud-net init -backend-config=backend.hcl
terraform -chdir=infra/terraform/stacks/40-xcloud-net apply       # ~30-45 min (VPN Gateway de Azure)
```

---

## 7. Activar el golden path B2 (MSK real + consumidores)

Con `use_self_hosted_kafka=false` (default), el bus es **MSK Serverless real** con
autenticación SASL/IAM. `create_iam_roles=true` (default) ya creó el usuario IAM
dedicado de solo-consumo en el paso 3.

```bash
# 1) Credenciales del bus (usuario IAM dedicado, permanente)
terraform -chdir=infra/terraform/stacks/10-aws-empi output kafka_bootstrap
terraform -chdir=infra/terraform/stacks/10-aws-empi output kafka_auth_mode                       # -> iam
terraform -chdir=infra/terraform/stacks/10-aws-empi output kafka_xcloud_access_key_id
terraform -chdir=infra/terraform/stacks/10-aws-empi output -raw kafka_xcloud_secret_access_key
```

Edita `infra/terraform/stacks/20-azure-integ/terraform.tfvars` y
`infra/terraform/stacks/30-gcp-analytics/terraform.tfvars`, agregando las 3 credenciales:

```hcl
kafka_bootstrap       = "<kafka_bootstrap>"
kafka_auth_mode       = "iam"
aws_access_key_id     = "<kafka_xcloud_access_key_id>"
aws_secret_access_key = "<kafka_xcloud_secret_access_key>"
```

Y en `20-azure-integ/terraform.tfvars` además: `enable_kafka_consumer = true`.

```bash
# 2) Re-aplica ambos stacks
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
`entregables_hito3/07_Scripts_Modelo_Datos/demo/postman_collection.json`, ajusta la
variable `base_url` al `patient_api_url` de este ambiente, y corre las 3 requests en orden.

---

## 9. Rotación de credenciales cross-cloud

La access key del usuario IAM `kafka_cross_cloud` (paso 7.1) es permanente. Rótala
periódicamente:

```bash
terraform -chdir=infra/terraform/stacks/10-aws-empi apply -replace="aws_iam_access_key.kafka_cross_cloud[0]"
# repite el paso 7 (2, 3) con las credenciales nuevas
```

---

*Perfil PROD · Complementa `DEPLOYMENT.demo.md` (cuentas de laboratorio) y `08_..._Plan_Puesta_En_Escena.md`.*
