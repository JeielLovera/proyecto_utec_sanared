output "grafana_url" {
  description = "URL de Grafana (login admin / grafana_admin_password). Restringido a admin_cidrs."
  value       = "http://${aws_lb.ui.dns_name}:3000"
}

output "jaeger_ui_url" {
  description = "URL de la UI de Jaeger (búsqueda de trazas directa, sin pasar por Grafana). Restringido a admin_cidrs."
  value       = "http://${aws_lb.ui.dns_name}:16686"
}

output "otlp_grpc_endpoint" {
  description = "Endpoint OTLP gRPC (host:puerto) para los exporters de las apps EMPI/hl7-adapter/gcp-consumer."
  value       = "${aws_lb.otlp.dns_name}:4317"
}

output "otlp_http_endpoint" {
  description = "Endpoint OTLP HTTP (host:puerto), alternativa si el runtime no soporta gRPC."
  value       = "${aws_lb.otlp.dns_name}:4318"
}

output "admin_cidrs_effective" {
  description = "CIDRs con acceso a Grafana/Jaeger UI (autodetectado si admin_cidrs quedó vacío)."
  value       = local.admin_cidrs
}

output "ecs_cluster" {
  value = aws_ecs_cluster.observability.name
}
