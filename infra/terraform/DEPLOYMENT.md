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
