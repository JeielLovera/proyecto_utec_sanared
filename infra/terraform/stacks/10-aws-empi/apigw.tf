# =============================================================================
# Edge PÚBLICO — API Gateway (REST regional) para pacientes (ADR-A3M-003).
# Integra por VPC Link -> NLB -> ECS. El WAF se asocia al stage (ver waf.tf).
# =============================================================================
resource "aws_api_gateway_rest_api" "public" {
  name        = "${local.name_prefix}-patient-api"
  description = "Entrada publica de pacientes al EMPI (portal)."

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_vpc_link" "api" {
  name        = "${local.name_prefix}-vpclink"
  target_arns = [aws_lb.api.arn]
}

# Proxy total: cualquier ruta/método -> NLB -> servicio EMPI.
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.public.id
  parent_id   = aws_api_gateway_rest_api.public.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.public.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.public.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.api.id
  uri                     = "http://${aws_lb.api.dns_name}/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_deployment" "public" {
  rest_api_id = aws_api_gateway_rest_api.public.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.proxy]
}

resource "aws_api_gateway_stage" "public" {
  rest_api_id   = aws_api_gateway_rest_api.public.id
  deployment_id = aws_api_gateway_deployment.public.id
  stage_name    = var.environment
}
