output "state_bucket" {
  description = "Nombre del bucket S3 del estado. Cópialo a backend.hcl de cada stack."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Tabla DynamoDB para el lock de estado."
  value       = aws_dynamodb_table.lock.name
}

output "region" {
  value = var.aws_region
}
