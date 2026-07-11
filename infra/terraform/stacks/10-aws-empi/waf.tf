# =============================================================================
# WAF (WAFv2 regional) sobre la entrada PÚBLICA del paciente (API Gateway).
# Protege el borde expuesto a internet (RNF-03). Los sistemas internos NO pasan por
# aquí (van por el ALB privado + mTLS) — perímetro por dirección (ADR-A3M-003).
# =============================================================================
resource "aws_wafv2_web_acl" "public" {
  name        = "${local.name_prefix}-waf"
  description = "WAF de la entrada pública del EMPI"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Reglas gestionadas por AWS (OWASP común).
  rule {
    name     = "common"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common"
      sampled_requests_enabled   = true
    }
  }

  # Límite de tasa por IP (anti-abuso).
  rule {
    name     = "rate-limit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "public" {
  resource_arn = aws_api_gateway_stage.public.arn
  web_acl_arn  = aws_wafv2_web_acl.public.arn
}
