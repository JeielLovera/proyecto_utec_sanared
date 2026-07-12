# IaC — EMPI Alternativa 3 Mejorada (multinube real)

Terraform que provisiona el **TO-BE del EMPI** en **AWS + Azure + GCP** para el Hito 3 de
Clínica SanaRed. Fiel a `entregables_hito3/03_..._Multicloud_Concordante.md` y al modelo de
datos de `entregables_hito3/07_..._Modelo_Datos.md`.

> **Alcance (importante):** el IaC despliega los componentes **del EMPI**, no los sistemas
> legados. HCE (Oracle), LIS (Azure SQL MI) y PACS son **AS-IS**: se integran, no se provisionan.
> Se representan con **endpoints simulados** (mock HL7, Orthanc para DICOM, Postgres "LIS").
> Esto no reduce la solución — la delimita a lo que el proyecto construye.

## Topología de stacks (estado remoto separado por stack)

```
infra/terraform/
├── bootstrap/            # (1º, estado LOCAL) crea el backend remoto: S3 + DynamoDB lock
├── stacks/
│   ├── 10-aws-empi/      # ★ FASE 1: núcleo EMPI (red, RDS, Redis, OpenSearch, MSK, ECS, edge)
│   ├── 20-azure-integ/   #   FASE 2: adaptadores HL7 (Functions), APIM egress, mock HCE
│   ├── 30-gcp-analytics/ #   FASE 3: Healthcare API (DICOM), BigQuery 360, Cloud Run
│   └── 40-xcloud-net/    #   FASE 2-3: túneles VPN IPSec AWS↔Azure↔GCP
└── modules/              # módulos reutilizables por recurso
```

Los stacks se cablean entre sí por `terraform_remote_state` (p. ej. `40-xcloud-net` lee los
IDs de VPC/VNet de los stacks de cada nube). Se aplican en orden: `bootstrap → 10 → 20/30 → 40`.

## Prerrequisitos (antes de `terraform apply`)

Herramientas (no instaladas aún en este equipo):

| Herramienta | Uso | Instalar |
|---|---|---|
| Terraform ≥ 1.6 | motor IaC | `winget install HashiCorp.Terraform` |
| AWS CLI v2 | credenciales AWS | `winget install Amazon.AWSCLI` |
| Azure CLI | credenciales Azure (Fase 2) | `winget install Microsoft.AzureCLI` |
| gcloud | credenciales GCP (Fase 3) | `winget install Google.CloudSDK` |
| checkov (opc.) | escaneo de seguridad del IaC | `pip install checkov` |

Credenciales / datos que debes proveer (van en `*.tfvars`, nunca al repo):

- **AWS:** cuenta con billing, `aws configure` (perfil), `aws_region` (default `us-east-1`).
- **Azure (Fase 2):** `subscription_id`, `tenant_id`, región.
- **GCP (Fase 3):** `project_id`, región, service account.

## Cómo arrancar (Fase 0 + Fase 1)

```bash
# 0) Backend remoto (una sola vez). Estado local -> crea S3+DynamoDB.
cd bootstrap
terraform init && terraform apply
#   anota los outputs: state_bucket, lock_table

# 1) Núcleo EMPI en AWS
cd ../stacks/10-aws-empi
cp backend.hcl.example backend.hcl          # pega el bucket del paso 0
cp terraform.tfvars.example terraform.tfvars # ajusta región, cidr, etc.
terraform init -backend-config=backend.hcl
terraform plan      # revisa
terraform apply
```

## Disciplina de costo (elegimos "3 nubes reales")

- SKUs **mínimos** por defecto (RDS `db.t4g.micro`, OpenSearch `t3.small.search` 1 nodo,
  ElastiCache `cache.t4g.micro`, **MSK Serverless**, 1 NAT Gateway).
- **`terraform destroy` al terminar cada sesión de demo.** El estado remoto permite recrear
  idéntico. Etiqueta `managed_by=terraform` en todo para barrido/auditoría de costo.
- `var.environment = "demo"` reduce tamaños; `"prod"` los sube (perfiles del doc §12).
- Nada de datos reales: solo sintéticos `es_PE` (RNF-07).

## Estado de construcción

| Fase | Stack / componente | Estado |
|---|---|---|
| 0 | `bootstrap` (S3+DynamoDB) + convenciones (providers/tags/perfiles) | ✅ escrito y `validate` OK |
| 1 | `10-aws-empi` · red (VPC/subredes/NAT/endpoints) | ✅ escrito y `validate` OK |
| 1 | `10-aws-empi` · seguridad (KMS, SSM umbrales, Secrets vía RDS-managed) | ✅ escrito y `validate` OK |
| 1 | `10-aws-empi` · datos (RDS PostgreSQL, ElastiCache Redis, OpenSearch) | ✅ escrito y `validate` OK |
| 1 | `10-aws-empi` · bus (MSK Serverless SASL/IAM) | ✅ escrito y `validate` OK |
| 2 | `services/empi-service/` (servicio EMPI, capa 2) | ✅ construido y **verificado E2E** |
| 1 | `10-aws-empi` · cómputo (ECR + ECS Fargate + IAM + logs) | ✅ escrito y `validate` OK |
| 1 | `10-aws-empi` · edge (API GW público+WAF, ALB privado+mTLS, NLB) | ✅ escrito y `validate` OK |
| 0/1 | CI GitHub Actions (fmt/validate/plan/checkov) | ✅ `.github/workflows/iac.yml` |
| 2 | `20-azure-integ` (VNet, Functions HL7, APIM egress, mock HCE) | ✅ escrito y `validate` OK |
| 2 | `40-xcloud-net` — tramo AWS↔Azure | ✅ escrito y `validate` OK |
| 2 | `services/hl7-adapter/` (ADT^A28/A40) | ✅ construido y **verificado** (pytest 3/3) |
| 3 | `30-gcp-analytics` (VPC, Healthcare API/DICOM, BigQuery 360, Cloud Run, Artifact Registry) | ✅ escrito y `validate` OK |
| 3 | `40-xcloud-net` — tramo AWS↔GCP (Classic VPN, mismo VGW) | ✅ escrito y `validate` OK |
| 3 | `services/gcp-consumer/` (re-tag DICOM + refresh patient_360) | ✅ construido y **verificado** (pytest 5/5) |
| 4 | **Wiring real del bus**: Redis cache-aside, productor Kafka (`bus.py`), consumidores standalone HL7/GCP | ✅ construido y **verificado E2E local** (Redpanda: productor→bus→ambos consumidores, HL7 entregó `ADT^A40` al HCE mock con `200 OK`) |
| 4 | IaC del wiring: `data.aws_msk_bootstrap_brokers`, usuario IAM cross-cloud, ACI consumidor HL7 (Azure), Cloud Run always-on (GCP) | ✅ escrito y `validate` OK (5 stacks) |
| 4 | Golden path B2 contra la nube real (credenciales de laboratorio) | ⬜ pendiente |
| 4 | Demo reproducible (seed sintético + script + evidencias) | ⬜ pendiente |

> `terraform validate` corre OK con Terraform 1.9.8. Falta `terraform plan/apply` real
> (requiere credenciales AWS) y el escaneo `checkov`.
