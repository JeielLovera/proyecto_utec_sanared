# Roles de las tareas ECS del servicio EMPI.
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
  name               = "${local.name_prefix}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
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
  name   = "secrets-access"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# --- Task role: identidad del proceso en runtime (bus MSK, lectura SSM en caliente) ---
resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
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
    resources = ["${aws_msk_serverless_cluster.bus.arn}", "${replace(aws_msk_serverless_cluster.bus.arn, ":cluster/", ":topic/")}/*", "${replace(aws_msk_serverless_cluster.bus.arn, ":cluster/", ":group/")}/*"]
  }
  statement {
    sid       = "ReadSsmRuntime"
    actions   = ["ssm:GetParameters", "ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/empi/${var.environment}/*"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "empi-runtime"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
