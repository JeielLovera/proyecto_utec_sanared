# Roles de las tareas ECS del servicio EMPI.
# En AWS Academy Learner Lab (iam:CreateRole bloqueado) usar create_iam_roles=false y
# lab_role_arn = "arn:aws:iam::<ACCOUNT>:role/LabRole".
locals {
  ecs_execution_role_arn = var.create_iam_roles ? aws_iam_role.execution[0].arn : var.lab_role_arn
  ecs_task_role_arn      = var.create_iam_roles ? aws_iam_role.task[0].arn : var.lab_role_arn
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- Execution role: ECS lo usa para arrancar la tarea (pull de ECR, logs, secretos) ---
resource "aws_iam_role" "execution" {
  count              = var.create_iam_roles ? 1 : 0
  name               = "${local.name_prefix}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  count      = var.create_iam_roles ? 1 : 0
  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Permite inyectar parámetros SSM y el secreto de RDS como variables de entorno.
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadSsm"
    actions   = ["ssm:GetParameters", "ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/empi/${var.environment}/*"]
  }
  statement {
    sid       = "ReadRdsSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.empi.master_user_secret[0].secret_arn]
  }
  statement {
    sid       = "DecryptKms"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.empi.arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count  = var.create_iam_roles ? 1 : 0
  name   = "secrets-access"
  role   = aws_iam_role.execution[0].id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# --- Task role: identidad del proceso en runtime (bus MSK, lectura SSM en caliente) ---
resource "aws_iam_role" "task" {
  count              = var.create_iam_roles ? 1 : 0
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task" {
  # Acceso al bus solo si MSK está habilitado.
  dynamic "statement" {
    for_each = var.enable_msk ? [1] : []
    content {
      sid = "KafkaConnect"
      actions = [
        "kafka-cluster:Connect",
        "kafka-cluster:DescribeCluster",
        "kafka-cluster:*Topic*",
        "kafka-cluster:WriteData",
        "kafka-cluster:ReadData",
        "kafka-cluster:AlterGroup",
        "kafka-cluster:DescribeGroup",
      ]
      resources = [
        aws_msk_serverless_cluster.bus[0].arn,
        "${replace(aws_msk_serverless_cluster.bus[0].arn, ":cluster/", ":topic/")}/*",
        "${replace(aws_msk_serverless_cluster.bus[0].arn, ":cluster/", ":group/")}/*",
      ]
    }
  }
  statement {
    sid       = "ReadSsmRuntime"
    actions   = ["ssm:GetParameters", "ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/empi/${var.environment}/*"]
  }
}

resource "aws_iam_role_policy" "task" {
  count  = var.create_iam_roles ? 1 : 0
  name   = "empi-runtime"
  role   = aws_iam_role.task[0].id
  policy = data.aws_iam_policy_document.task.json
}
