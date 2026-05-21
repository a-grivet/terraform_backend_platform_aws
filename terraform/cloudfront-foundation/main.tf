data "aws_caller_identity" "current" {}

locals {
  web_acl_name   = "inca-waf-cloudfront-${var.environment}"
  log_group_name = "aws-waf-logs-inca-cloudfront-${var.environment}"
  common_tags    = merge(var.tags, { environment = var.environment })
}

# ---------------------------------------------------------------------------
# Remote state — read API IDs from upload and deployment foundations
# ---------------------------------------------------------------------------

data "terraform_remote_state" "upload" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = var.upload_foundation_state_key
    region = var.aws_region
  }
}

data "terraform_remote_state" "deployment" {
  backend = "s3"
  config = {
    bucket = var.terraform_state_bucket
    key    = var.deployment_foundation_state_key
    region = var.aws_region
  }
}

locals {
  # try() allows destroy to succeed when the upstream stacks have already been
  # torn down and their remote state outputs no longer exist. The fallback value
  # is never used during apply — only during destroy where Terraform reads
  # origin domains from state rather than from these locals.
  upload_api_domain     = try("${data.terraform_remote_state.upload.outputs.upload_http_api_id}.execute-api.${var.aws_region}.amazonaws.com", "destroyed.execute-api.${var.aws_region}.amazonaws.com")
  deployment_api_domain = try("${data.terraform_remote_state.deployment.outputs.deployment_api_id}.execute-api.${var.aws_region}.amazonaws.com", "destroyed.execute-api.${var.aws_region}.amazonaws.com")
  api_stage_path        = "/api"
}

# ---------------------------------------------------------------------------
# CloudWatch Logs — WAF CLOUDFRONT log group must be in us-east-1
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "waf_cloudfront" {
  provider          = aws.us_east_1
  name              = local.log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_resource_policy" "waf_cloudfront" {
  provider    = aws.us_east_1
  policy_name = "waf-cloudfront-logs-${var.environment}"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.waf_cloudfront.arn}:*"
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
  provider = aws.us_east_1
  count    = length(var.ip_allowlist) > 0 ? 1 : 0

  name               = "inca-waf-cf-allowlist-${var.environment}"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.ip_allowlist

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# WAF Web ACL — CLOUDFRONT scope (must be in us-east-1)
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = local.web_acl_name
  scope       = "CLOUDFRONT"
  description = "Protects INCA upload and deployment APIs via CloudFront."

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

  # Rule 3: Rate limiting per IP
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

resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  provider                = aws.us_east_1
  log_destination_configs = [aws_cloudwatch_log_group.waf_cloudfront.arn]
  resource_arn            = aws_wafv2_web_acl.cloudfront.arn

  depends_on = [aws_cloudwatch_log_resource_policy.waf_cloudfront]
}

# ---------------------------------------------------------------------------
# CloudFront — Upload API
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "upload" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "INCA Upload API (${var.environment})"
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name = local.upload_api_domain
    origin_id   = "inca-upload-api-${var.environment}"
    origin_path = local.api_stage_path

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "inca-upload-api-${var.environment}"
    viewer_protocol_policy = "https-only"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    # No caching — API responses are dynamic.
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled (AWS managed)
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader (AWS managed)

    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # WAF handles geo-restriction
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# CloudFront — Deployment API
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "deployment" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "INCA Deployment API (${var.environment})"
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name = local.deployment_api_domain
    origin_id   = "inca-deployment-api-${var.environment}"
    origin_path = local.api_stage_path

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "inca-deployment-api-${var.environment}"
    viewer_protocol_policy = "https-only"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled (AWS managed)
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader (AWS managed)

    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # WAF handles geo-restriction
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}
