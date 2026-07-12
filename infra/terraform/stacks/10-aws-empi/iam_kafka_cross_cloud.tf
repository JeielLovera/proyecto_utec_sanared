# =============================================================================
# Credencial IAM para consumidores CROSS-CLOUD del bus GESTIONADO (MSK Serverless).
# Fuera de AWS no hay rol de tarea que asumir: se usa un usuario IAM dedicado, de
# solo consumo, con una access key. Se distribuye vía outputs de 40-xcloud-net.
#
# Solo aplica con use_kafka_managed (MSK). El bus self-hosted (Redpanda) no usa IAM
# (perímetro por security group), así que estos recursos no existen en ese modo.
# Gateado además por create_iam_roles: en Learner Lab (iam:CreateUser también
# bloqueado) no se puede crear; usa credenciales temporales de tu sesión en su lugar
# (ver DEPLOYMENT.md §6.1) o cambia a use_self_hosted_kafka=true.
# =============================================================================
resource "aws_iam_user" "kafka_cross_cloud" {
  count = var.create_iam_roles && local.use_kafka_managed ? 1 : 0
  name  = "${local.name_prefix}-kafka-xcloud"
}

data "aws_iam_policy_document" "kafka_cross_cloud" {
  count = local.use_kafka_managed ? 1 : 0
  statement {
    sid = "KafkaConsumeOnly"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:ReadData",
      "kafka-cluster:DescribeGroup",
      "kafka-cluster:AlterGroup",
    ]
    resources = [
      aws_msk_serverless_cluster.bus[0].arn,
      "${replace(aws_msk_serverless_cluster.bus[0].arn, ":cluster/", ":topic/")}/identity.patient.*",
      "${replace(aws_msk_serverless_cluster.bus[0].arn, ":cluster/", ":group/")}/*",
    ]
  }
}

resource "aws_iam_user_policy" "kafka_cross_cloud" {
  count  = var.create_iam_roles && local.use_kafka_managed ? 1 : 0
  name   = "kafka-consume-only"
  user   = aws_iam_user.kafka_cross_cloud[0].name
  policy = data.aws_iam_policy_document.kafka_cross_cloud[0].json
}

resource "aws_iam_access_key" "kafka_cross_cloud" {
  count = var.create_iam_roles && local.use_kafka_managed ? 1 : 0
  user  = aws_iam_user.kafka_cross_cloud[0].name
}
