provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  upload_bucket_name = coalesce(
    var.upload_bucket_name,
    "inca-terraform-${var.environment}-${data.aws_caller_identity.current.account_id}"
  )
  upload_bucket_region = coalesce(var.upload_bucket_region, var.aws_region)
  upload_intents_table_name = coalesce(
    var.dynamodb_table_name,
    "inca-upload-intents-${var.environment}"
  )
  prepare_lambda_role_name = coalesce(
    var.lambda_role_name,
    "prepare-template-upload-lambda-role-${var.environment}"
  )
  prepare_lambda_policy_name = coalesce(
    var.lambda_policy_name,
    "prepare-template-upload-lambda-policy-${var.environment}"
  )
  prepare_lambda_function_name = coalesce(
    var.lambda_function_name,
    "prepare-template-upload-${var.environment}"
  )
  complete_lambda_role_name = coalesce(
    var.complete_lambda_role_name,
    "complete-template-upload-lambda-role-${var.environment}"
  )
  complete_lambda_policy_name = coalesce(
    var.complete_lambda_policy_name,
    "complete-template-upload-lambda-policy-${var.environment}"
  )
  complete_lambda_function_name = coalesce(
    var.complete_lambda_function_name,
    "complete-template-upload-${var.environment}"
  )
  upload_http_api_name = coalesce(
    var.http_api_name,
    "inca-upload-api-${var.environment}"
  )
  # Temporarily disabled: custom domain + ACM + Route53 automation.
  # Re-enable by restoring the flag below and the resources further down.
  # upload_http_api_custom_domain_enabled = var.http_api_custom_domain_name != null && var.hosted_zone_id != null

  prepare_lambda_source_file  = "${path.module}/../../lambdas/prepare-upload/handler.py"
  prepare_lambda_output_zip   = "${path.module}/prepare-template-upload.zip"
  complete_lambda_source_file = "${path.module}/../../lambdas/complete-upload/handler.py"
  complete_lambda_output_zip  = "${path.module}/complete-template-upload.zip"

  common_tags = merge(var.tags, {
    environment = var.environment
  })
}

resource "aws_s3_bucket" "raw_uploads" {
  bucket        = local.upload_bucket_name
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encrypt_with_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.encrypt_with_kms ? var.kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT"]
    allowed_origins = var.allowed_cors_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 300
  }
}

resource "aws_s3_bucket_notification" "raw_uploads" {
  bucket = aws_s3_bucket.raw_uploads.id

  eventbridge = true
}

resource "aws_s3_object" "blueprint_lifecycle_prefixes" {
  for_each = toset([
    "blueprints/pending/",
    "blueprints/validated/",
    "blueprints/rejected/",
    "blueprints/deployed/",
  ])

  bucket       = aws_s3_bucket.raw_uploads.id
  key          = each.value
  content      = ""
  content_type = "application/x-directory"
}

resource "aws_dynamodb_table" "upload_intents" {
  name         = local.upload_intents_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "template_id"
  range_key    = "version_id"

  attribute {
    name = "template_id"
    type = "S"
  }

  attribute {
    name = "version_id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.encrypt_with_kms ? var.kms_key_arn : null
  }

  tags = local.common_tags
}

data "aws_iam_policy_document" "prepare_upload_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "prepare_upload_lambda" {
  name               = local.prepare_lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.prepare_upload_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role" "complete_upload_lambda" {
  name               = local.complete_lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.prepare_upload_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "prepare_upload_lambda" {
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  statement {
    sid    = "AllowUploadIntentTableWrites"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query"
    ]

    resources = [aws_dynamodb_table.upload_intents.arn]
  }

  statement {
    sid    = "AllowRawUploadBucketAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:HeadObject",
      "s3:PutObject"
    ]

    resources = ["${aws_s3_bucket.raw_uploads.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.encrypt_with_kms ? [1] : []

    content {
      sid    = "AllowKmsForUploadFoundation"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]

      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "prepare_upload_lambda" {
  name   = local.prepare_lambda_policy_name
  policy = data.aws_iam_policy_document.prepare_upload_lambda.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "prepare_upload_lambda" {
  role       = aws_iam_role.prepare_upload_lambda.name
  policy_arn = aws_iam_policy.prepare_upload_lambda.arn
}

resource "aws_iam_policy" "complete_upload_lambda" {
  name   = local.complete_lambda_policy_name
  policy = data.aws_iam_policy_document.prepare_upload_lambda.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "complete_upload_lambda" {
  role       = aws_iam_role.complete_upload_lambda.name
  policy_arn = aws_iam_policy.complete_upload_lambda.arn
}

data "archive_file" "prepare_upload_lambda" {
  type        = "zip"
  source_file = local.prepare_lambda_source_file
  output_path = local.prepare_lambda_output_zip
}

data "archive_file" "complete_upload_lambda" {
  type        = "zip"
  source_file = local.complete_lambda_source_file
  output_path = local.complete_lambda_output_zip
}

resource "aws_lambda_function" "prepare_upload" {
  function_name    = local.prepare_lambda_function_name
  role             = aws_iam_role.prepare_upload_lambda.arn
  runtime          = var.lambda_runtime
  handler          = var.lambda_handler
  filename         = data.archive_file.prepare_upload_lambda.output_path
  source_code_hash = data.archive_file.prepare_upload_lambda.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  memory_size      = var.lambda_memory_size_mb

  environment {
    variables = {
      UPLOAD_BUCKET_NAME               = aws_s3_bucket.raw_uploads.bucket
      UPLOAD_BUCKET_REGION             = local.upload_bucket_region
      UPLOAD_INTENTS_TABLE_NAME        = aws_dynamodb_table.upload_intents.name
      MAX_UPLOAD_SIZE_BYTES            = tostring(var.max_upload_size_bytes)
      PRESIGNED_URL_EXPIRATION_SECONDS = tostring(var.presigned_url_expiration_seconds)
    }
  }

  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.prepare_upload.name
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  tags = local.common_tags
}

resource "aws_lambda_function" "complete_upload" {
  function_name    = local.complete_lambda_function_name
  role             = aws_iam_role.complete_upload_lambda.arn
  runtime          = var.lambda_runtime
  handler          = var.lambda_handler
  filename         = data.archive_file.complete_upload_lambda.output_path
  source_code_hash = data.archive_file.complete_upload_lambda.output_base64sha256
  timeout          = var.lambda_timeout_seconds
  memory_size      = var.lambda_memory_size_mb

  environment {
    variables = {
      UPLOAD_BUCKET_NAME        = aws_s3_bucket.raw_uploads.bucket
      UPLOAD_INTENTS_TABLE_NAME = aws_dynamodb_table.upload_intents.name
    }
  }

  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.complete_upload.name
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "prepare_upload" {
  name              = "/aws/lambda/${local.prepare_lambda_function_name}"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "complete_upload" {
  name              = "/aws/lambda/${local.complete_lambda_function_name}"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "upload_api_access_logs" {
  name              = "/aws/apigatewayv2/${local.upload_http_api_name}"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.common_tags
}

resource "aws_apigatewayv2_api" "upload" {
  name          = local.upload_http_api_name
  protocol_type = "HTTP"

  # Temporarily disabled: API Gateway CORS configuration added for frontend integration.
  # dynamic "cors_configuration" {
  #   for_each = length(var.api_allowed_cors_origins) > 0 ? [1] : []
  #
  #   content {
  #     allow_credentials = var.api_allow_credentials
  #     allow_headers     = var.api_allowed_cors_headers
  #     allow_methods     = var.api_allowed_cors_methods
  #     allow_origins     = var.api_allowed_cors_origins
  #     max_age           = var.api_cors_max_age_seconds
  #   }
  # }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "prepare_upload" {
  api_id                 = aws_apigatewayv2_api.upload.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.prepare_upload.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "prepare_upload" {
  api_id    = aws_apigatewayv2_api.upload.id
  route_key = "POST /templates/uploads/prepare"
  target    = "integrations/${aws_apigatewayv2_integration.prepare_upload.id}"
}

resource "aws_apigatewayv2_integration" "complete_upload" {
  api_id                 = aws_apigatewayv2_api.upload.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.complete_upload.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "complete_upload" {
  api_id    = aws_apigatewayv2_api.upload.id
  route_key = "POST /templates/uploads/complete"
  target    = "integrations/${aws_apigatewayv2_integration.complete_upload.id}"
}

resource "aws_apigatewayv2_stage" "upload" {
  api_id      = aws_apigatewayv2_api.upload.id
  name        = var.http_api_stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.upload_api_access_logs.arn
    format = jsonencode({
      requestId            = "$context.requestId"
      ip                   = "$context.identity.sourceIp"
      requestTime          = "$context.requestTime"
      httpMethod           = "$context.httpMethod"
      routeKey             = "$context.routeKey"
      status               = "$context.status"
      protocol             = "$context.protocol"
      responseLength       = "$context.responseLength"
      responseLatencyMs    = "$context.responseLatency"
      integrationLatencyMs = "$context.integrationLatency"
      integrationStatus    = "$context.integrationStatus"
      errorMessage         = "$context.error.message"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = var.http_api_throttling_burst_limit
    throttling_rate_limit    = var.http_api_throttling_rate_limit
  }

  tags = local.common_tags
}

# Temporarily disabled: ACM certificate + DNS validation + API Gateway custom domain + Route53 alias.
#
# resource "aws_acm_certificate" "upload_http_api" {
#   count             = local.upload_http_api_custom_domain_enabled ? 1 : 0
#   domain_name       = var.http_api_custom_domain_name
#   validation_method = "DNS"
#
#   tags = merge(local.common_tags, {
#     Name = var.http_api_custom_domain_name
#   })
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }
#
# resource "aws_route53_record" "upload_http_api_certificate_validation" {
#   for_each = local.upload_http_api_custom_domain_enabled ? {
#     for dvo in aws_acm_certificate.upload_http_api[0].domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   } : {}
#
#   allow_overwrite = true
#   name            = each.value.name
#   records         = [each.value.record]
#   ttl             = 60
#   type            = each.value.type
#   zone_id         = var.hosted_zone_id
# }
#
# resource "aws_acm_certificate_validation" "upload_http_api" {
#   count                   = local.upload_http_api_custom_domain_enabled ? 1 : 0
#   certificate_arn         = aws_acm_certificate.upload_http_api[0].arn
#   validation_record_fqdns = [for record in aws_route53_record.upload_http_api_certificate_validation : record.fqdn]
# }
#
# resource "aws_apigatewayv2_domain_name" "upload" {
#   count       = local.upload_http_api_custom_domain_enabled ? 1 : 0
#   domain_name = var.http_api_custom_domain_name
#
#   domain_name_configuration {
#     certificate_arn = aws_acm_certificate_validation.upload_http_api[0].certificate_arn
#     endpoint_type   = "REGIONAL"
#     security_policy = "TLS_1_2"
#   }
#
#   tags = local.common_tags
# }
#
# resource "aws_apigatewayv2_api_mapping" "upload" {
#   count       = local.upload_http_api_custom_domain_enabled ? 1 : 0
#   api_id      = aws_apigatewayv2_api.upload.id
#   domain_name = aws_apigatewayv2_domain_name.upload[0].id
#   stage       = aws_apigatewayv2_stage.upload.id
# }
#
# resource "aws_route53_record" "upload_http_api" {
#   count   = local.upload_http_api_custom_domain_enabled ? 1 : 0
#   name    = aws_apigatewayv2_domain_name.upload[0].domain_name
#   type    = "A"
#   zone_id = var.hosted_zone_id
#
#   alias {
#     evaluate_target_health = false
#     name                   = aws_apigatewayv2_domain_name.upload[0].domain_name_configuration[0].target_domain_name
#     zone_id                = aws_apigatewayv2_domain_name.upload[0].domain_name_configuration[0].hosted_zone_id
#   }
# }

resource "aws_lambda_permission" "allow_apigateway_prepare_upload" {
  statement_id  = "AllowHttpApiInvokePrepareUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prepare_upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.upload.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_apigateway_complete_upload" {
  statement_id  = "AllowHttpApiInvokeCompleteUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.complete_upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.upload.execution_arn}/*/*"
}

resource "aws_sns_topic" "upload_alerts" {
  name = "inca-upload-alerts-${var.environment}"
  tags = local.common_tags
}

resource "aws_sns_topic_policy" "upload_alerts" {
  arn = aws_sns_topic.upload_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.upload_alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "upload_alerts_email" {
  count     = var.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.upload_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "prepare_upload_lambda_errors" {
  alarm_name          = "inca-prepare-upload-lambda-errors-${var.environment}"
  alarm_description   = "Triggers when the prepare-upload Lambda returns errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.prepare_upload.function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.upload_alerts.arn]
  ok_actions    = [aws_sns_topic.upload_alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "complete_upload_lambda_errors" {
  alarm_name          = "inca-complete-upload-lambda-errors-${var.environment}"
  alarm_description   = "Triggers when the complete-upload Lambda returns errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.complete_upload.function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.upload_alerts.arn]
  ok_actions    = [aws_sns_topic.upload_alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "upload_api_5xx_errors" {
  alarm_name          = "inca-upload-api-5xx-${var.environment}"
  alarm_description   = "Upload API Gateway 5xx errors — Lambda integration failures."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.upload.id }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.upload_alerts.arn]
  ok_actions    = [aws_sns_topic.upload_alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "upload_api_4xx_errors" {
  alarm_name          = "inca-upload-api-4xx-${var.environment}"
  alarm_description   = "Upload API Gateway 4xx errors — sustained rate suggests auth issues or bad clients."
  namespace           = "AWS/ApiGateway"
  metric_name         = "4xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.upload.id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.upload_alerts.arn]
  ok_actions    = [aws_sns_topic.upload_alerts.arn]

  tags = local.common_tags
}
