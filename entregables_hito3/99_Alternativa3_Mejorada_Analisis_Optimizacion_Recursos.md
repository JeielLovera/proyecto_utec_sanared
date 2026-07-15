# Análisis de Optimización de Recursos — Alternativa 3 Mejorada (EMPI Multicloud)
## Iniciativa: Identidad Unificada de Pacientes (EMPI) | INI-01 / INI-13 | Clínica SanaRed Integrada | Hito 3

> **Qué es este documento:** una revisión de la infraestructura como código (IaC) desplegada para responder una pregunta concreta que surgió al ver el despliegue real: **¿son necesarios todos los recursos que se crean, en especial en AWS?** El análisis distingue entre lo que es *estructural* (no se debe recortar) y lo que se puede **simplificar sin eliminar la capacidad** (llevarlo a su forma más básica, como usar un servicio gestionado en su SKU mínimo en vez de una versión completa).
>
> **Alcance:** análisis estático del código Terraform en `infra/terraform/stacks/`. No modifica la infraestructura; es una guía de decisiones de optimización.

---

## 1. Contexto: de dónde salen los ~82 recursos de AWS

Al desplegar el perfil demo/lab (`10-aws-empi`, `terraform.tfvars.lab.example`) se crean **82 recursos** en AWS. Esa cifra sorprende a primera vista, pero no proviene de recursos "de más": proviene de **tres bloques funcionales grandes más el andamiaje estructural** que cualquier VPC segura necesita.

| Bloque | Recursos (perfil lab) | Qué es |
|---|---|---|
| Andamiaje de red (`modules/aws-network`) | ~19 | VPC, 2+2 subredes (pública/privada × 2 AZ), IGW, NAT, route tables, S3 gateway endpoint |
| Edge público — paciente | 12 | API Gateway + WAF + VPC Link + NLB |
| **Edge interno — admisión (mTLS)** | **19** | ALB privado + PKI de demo (CA, cert de servidor, cert de cliente) + bucket S3 del trust store |
| Bus de eventos self-hosted (Redpanda) | 8 | Tarea ECS + NLB + security group + parámetro SSM |
| Datos | 6 | RDS PostgreSQL + ElastiCache Redis + KMS CMK |
| Cómputo + seguridad + config | ~18 | ECS/ECR/CloudWatch Logs, 3 security groups, 8 parámetros SSM |

### Matiz clave: conteo de recursos ≠ costo

**"82 recursos" no significa "82 cosas caras."** Buena parte del edge interno mTLS (19 recursos) son objetos del provider `tls` — llaves privadas y certificados generados **localmente por Terraform, con costo cloud de $0**. Inflan el *conteo* de recursos pero no la *factura*. Lo verdaderamente facturable en ese bloque es el ALB (1), el certificado ACM (gratis) y el bucket S3 del trust store (centavos).

De forma similar, los 8 parámetros SSM y los security groups son gratuitos o de costo despreciable. El costo real se concentra en: RDS, ElastiCache, los balanceadores (ALB/NLB), el NAT Gateway y las tareas ECS Fargate.

---

## 2. Andamiaje estructural — NO recortar

Estos recursos son la base de un despliegue seguro y aislado. Recortarlos rompería el aislamiento de red o el principio de menor privilegio; se documentan aquí explícitamente para evitar "optimizaciones" que degraden la postura de seguridad.

| Recurso | Por qué NO se recorta |
|---|---|
| VPC + subredes públicas/privadas | Aislamiento de red. RDS/Redis/OpenSearch viven en subredes **privadas** sin IP pública (RNF-03). |
| NAT Gateway (1 en demo) | Ya es la opción **más simple**. La alternativa "privada pura" (interface VPC endpoints para ECR/logs/SSM/Secrets) **agregaría ~5 recursos**, no los quita. |
| Security groups por servicio (app/rds/redis) | Menor privilegio: solo el SG de la app alcanza RDS/Redis. Colapsarlos abriría el plano de datos. |
| Route tables, IGW, S3 gateway endpoint | Enrutamiento base. El endpoint S3 evita costo de datos hacia S3. |

**Sobre reducir a 1 sola AZ:** bajar `az_count` de 2 a 1 quitaría ~4 recursos, pero elimina la alta disponibilidad (RNF-02) y contradice la topología multi-AZ del documento §12. No recomendado salvo para una demo puramente descartable.

---

## 3. Cuadro comparativo — dónde SÍ se puede simplificar sin eliminar

Cada ítem **conserva la capacidad**; solo la lleva a su forma más básica o la vuelve *opt-in* (encendible cuando se necesita mostrar), siguiendo el patrón que el IaC ya usa con `enable_opensearch`.

| # | Recurso/grupo | Estado hoy | Forma más básica (sin eliminar la capacidad) | Ahorro | Trade-off |
|---|---|---|---|---|---|
| 1 | **Edge interno mTLS** (`alb.tf` + `alb_mtls_client_demo.tf`) | 19 recursos, siempre desplegados | Volverlo **opt-in** con un flag `enable_internal_mtls` (igual que `enable_opensearch`). Se enciende solo para el ejercicio del admisionista | **−19** en el apply base | Ninguno real: la capacidad sigue en el código, solo no se levanta por defecto |
| 2 | **VPN cross-cloud** (stack `40-xcloud-net`) | 20 recursos + **~27 min** de gateway Azure al crear | En demo, bus **público con TLS** en vez de VPN privada — opción ya contemplada en el C4 Model (*"en el lab basta conectividad pública con TLS, sin los enlaces privados de producción"*). La VPN queda para el perfil prod | **−20 recursos y ~30 min** | Se pierde la demostración *en vivo* del enlace privado; el flujo funcional cross-cloud (eventos llegando a Azure/GCP) es idéntico |
| 3 | **Redis / ElastiCache** (`redis.tf` + SG + SSM) | 4 recursos, siempre desplegados | Flag `enable_redis`. **La app degrada sola** (`config.py`: *"Caché de identidad opcional; si es None se omite el Paso 1 por Redis"*) | **−4** | El matcher salta el Paso 1 (lookup por cache); en volumen de demo es imperceptible |
| 4 | **KMS CMK propia** (`kms.tf`) | 2 recursos (key + alias) + política IAM de descifrado | Usar **claves gestionadas por AWS** (`aws/rds`, `aws/elasticache`, `aws/secretsmanager`) — el cifrado en reposo sigue activo | **−2** + IAM más simple | Se pierde la narrativa "una sola CMK para todo el PII" con rotación controlada (RNF-03, Ley 29733) |
| 5 | **Edge público API GW + NLB** (`apigw.tf` + `nlb.tf` + `waf.tf`) | 12 recursos (API Gateway + VPC Link + NLB + WAF) | **ALB + WAF directo** (el ALB soporta asociación WAFv2 sin VPC Link ni NLB intermedio) | **−7** | Cambia la narrativa "API Gateway" → "ALB"; se pierden throttling / API keys / usage plans (no usados en la demo) |
| 6 | Route tables privadas | 2 (una por AZ) | 1 compartida cuando `single_nat_gateway=true` (todas apuntan al mismo NAT) | −1 | Marginal |
| 7 | Parámetros SSM de descubrimiento (`db_host`, `db_port`, `db_name`, `db_secret_arn`, `redis_endpoint`) | 5 parámetros | Pasarlos como variables de entorno directas de ECS. **Mantener los 3 de umbrales** (`threshold_auto/review`, `model_version`) — esos sí son configuración *hot-reload* real (RNF-06.2) | −5 | Marginal (SSM Parameter Store es free tier) |

---

## 4. Notas por stack (más allá de AWS)

- **`20-azure-integ` (10 recursos)** — ya está en su forma mínima para el lab: APIM deshabilitado (`enable_apim=false`, ahorra ~30-45 min y costo), Function App deshabilitada (cuota 0 en la suscripción académica), y el consumo real corre en un Azure Container Instance de 0.5 vCPU. No hay recorte evidente sin perder el consumidor HL7.
- **`30-gcp-analytics` (20 recursos)** — Cloud Run con `min_instances=1` (necesario para mantener vivo el hilo consumidor de Kafka), BigQuery, Healthcare API. El conector VPC Access (~2-3 min de creación) es la pieza más pesada; es necesario para que Cloud Run alcance el bus por red privada. Sin recorte evidente en el modo cross-cloud real.
- **`40-xcloud-net` (20 recursos)** — ver ítem #2. Es el **mayor palanca de tiempo** del redespliegue (gateway VPN de Azure: ~27 min crear, ~10 min destruir).
- **`50-observability` (16 recursos)** — Jaeger + Grafana ya corren en **una sola tarea Fargate** (forma mínima). Optimización menor posible: unificar el NLB público (UI) con el interno (OTLP) y acceder a la UI por túnel SSM en vez de un balanceador público (−~5 recursos), a cambio de perder el acceso directo por URL.

---

## 5. Recomendación

Si el objetivo es un **redespliegue de demostración más liviano y rápido** (p. ej. para una presentación), las dos palancas que mueven la aguja de verdad son **#1 y #2**:

| Escenario | Recursos totales (aprox.) | Tiempo del cuello de botella |
|---|---|---|
| Completo (como está hoy) | ~148 (5 stacks) | Gateway VPN Azure ~27 min |
| Demo mínima (aplicando #1 + #2) | ~110 | Sin gateway VPN |

Ambas se implementarían como **flags nuevos** (`enable_internal_mtls`, y un modo `bus_public_tls` para saltar la VPN en demo), siguiendo el patrón que el IaC ya usa con `enable_opensearch` / `use_self_hosted_kafka`: **no rompen el perfil de producción**, solo agregan un modo "demo mínima".

Los ítems #3–#7 son de menor impacto (recuento) y algunos tienen costo prácticamente nulo hoy, por lo que su valor está más en la claridad conceptual ("qué es imprescindible vs. qué es opcional") que en el ahorro real.

### Principio general

La mayoría de los 82 recursos de AWS **son necesarios** y responden a decisiones deliberadas: aislamiento de red, menor privilegio, cifrado, y los **dos perímetros de entrada por dirección** (público con WAF / interno con mTLS, ADR-A3M-003). Lo que sí es legítimo optimizar es **cuáles de esas capacidades se levantan por defecto**: separar la "demo mínima que muestra el golden path" de la "topología completa que demuestra cada perímetro y el enlace privado cross-cloud", en lugar de desplegar siempre todo.

---

*Documento de Hito 3 — Análisis de Optimización de Recursos de la Alternativa 3 Mejorada | Iniciativa EMPI | Clínica SanaRed Integrada*
*Basado en el análisis estático de `infra/terraform/stacks/` (stacks 10 a 50).*
