# =============================================================================
# Plano 1 (Event Store) + Plano 2 (proyecciones CQRS) — RDS PostgreSQL
# Ref: 07_..._Modelo_Datos.md §2/§3. Se inicializa con entregables_hito3/
#      07_Scripts_Modelo_Datos/sql/ (ver nota de migraciones abajo).
# =============================================================================
resource "aws_db_subnet_group" "empi" {
  name       = "${local.name_prefix}-rds"
  subnet_ids = module.network.private_subnet_ids
  tags       = { Name = "${local.name_prefix}-rds" }
}

resource "aws_db_instance" "empi" {
  identifier     = "${local.name_prefix}-empi"
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = local.this.rds_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.empi.arn

  db_name  = "empi"
  username = "empi_admin"
  # AWS gestiona la contraseña maestra en Secrets Manager (cifrada con nuestra CMK).
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.empi.key_id

  db_subnet_group_name   = aws_db_subnet_group.empi.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = local.this.rds_multi_az

  backup_retention_period = var.environment == "prod" ? 7 : 1
  deletion_protection     = var.environment == "prod"
  skip_final_snapshot     = var.environment != "prod"
  apply_immediately       = true

  # Auditoría de conexiones (RNF-03)
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = "${local.name_prefix}-empi" }
}

# NOTA sobre migraciones (init con nuestros sql/):
#   RDS vive en subredes PRIVADAS (no accesible desde el equipo local). Los scripts
#   entregables_hito3/07_Scripts_Modelo_Datos/sql/{00..99}.sql se aplican desde DENTRO
#   de la VPC: por el runner de CI con acceso a la VPC, por la tarea ECS de arranque
#   del servicio EMPI (migración al boot), o por un bastion efímero. No se ejecutan
#   desde Terraform para no acoplar el ciclo de vida del esquema al de la infraestructura.
