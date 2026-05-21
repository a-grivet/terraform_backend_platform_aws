data "aws_caller_identity" "current" {}

locals {
  web_acl_name   = "inca-waf-${var.environment}"
  log_group_name = "aws-waf-logs-inca-${var.environment}"
  common_tags    = merge(var.tags, { environment = var.environment })
}

# ---------------------------------------------------------------------------
# CloudWatch Logs — WAF log group name MUST start with aws-waf-logs-
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "waf" {
  name              = local.log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  policy_name = "waf-logs-${var.environment}"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.waf.arn}:*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# IP allowlist — CIDRs that bypass all rules (CI runners, admin)
# ---------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "allowlist" {
  count = length(var.ip_allowlist) > 0 ? 1 : 0

  name               = "inca-waf-allowlist-${var.environment}"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.ip_allowlist

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Web ACL
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "main" {
  name        = local.web_acl_name
  scope       = "REGIONAL"
  description = "Protects INCA upload/deployment APIs and Cognito user pool."

  default_action {
    allow {}
  }

  # Rule 1: IP allowlist — bypasses all other rules (highest priority)
  dynamic "rule" {
    for_each = length(var.ip_allowlist) > 0 ? [1] : []
    content {
      name     = "IPAllowlist"
      priority = 1

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowlist[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IPAllowlist"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule 2: Geo-block — allow only configured countries, block everything else.
  # Omitted when allowed_country_codes is empty (e.g. dev with CI runner outside FR).
  dynamic "rule" {
    for_each = length(var.allowed_country_codes) > 0 ? [1] : []
    content {
      name     = "GeoBlockNonAllowedCountries"
      priority = 2

      action {
        block {}
      }

      statement {
        not_statement {
          statement {
            geo_match_statement {
              country_codes = var.allowed_country_codes
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "GeoBlockNonAllowedCountries"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule 3: Rate limiting per IP — protects against brute force and abuse
  rule {
    name     = "RateLimitPerIP"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_ip
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: AWS Managed Rules — Common Rule Set (OWASP Top 10)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: AWS Managed Rules — Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.web_acl_name
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# WAF logging → CloudWatch Logs
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}
