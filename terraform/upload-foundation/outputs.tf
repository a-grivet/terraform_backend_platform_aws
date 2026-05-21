output "aws_account_id" {
  description = "AWS account ID where the upload foundation resources are created."
  value       = data.aws_caller_identity.current.account_id
}

output "upload_bucket_name" {
  description = "S3 bucket used for raw Terraform uploads."
  value       = aws_s3_bucket.raw_uploads.bucket
}

output "upload_bucket_arn" {
  description = "S3 bucket ARN used for raw Terraform uploads."
  value       = aws_s3_bucket.raw_uploads.arn
}

output "upload_intents_table_name" {
  description = "DynamoDB table name storing upload intent metadata."
  value       = aws_dynamodb_table.upload_intents.name
}

output "upload_intents_table_arn" {
  description = "DynamoDB table ARN storing upload intent metadata."
  value       = aws_dynamodb_table.upload_intents.arn
}

output "prepare_template_upload_lambda_role_name" {
  description = "IAM role name for the prepare-template-upload Lambda function."
  value       = aws_iam_role.prepare_upload_lambda.name
}

output "prepare_template_upload_lambda_role_arn" {
  description = "IAM role ARN for the prepare-template-upload Lambda function."
  value       = aws_iam_role.prepare_upload_lambda.arn
}

output "prepare_template_upload_lambda_function_name" {
  description = "Lambda function name for the prepare-template-upload handler."
  value       = aws_lambda_function.prepare_upload.function_name
}

output "prepare_template_upload_lambda_function_arn" {
  description = "Lambda function ARN for the prepare-template-upload handler."
  value       = aws_lambda_function.prepare_upload.arn
}

output "complete_template_upload_lambda_role_name" {
  description = "IAM role name for the complete-template-upload Lambda function."
  value       = aws_iam_role.complete_upload_lambda.name
}

output "complete_template_upload_lambda_role_arn" {
  description = "IAM role ARN for the complete-template-upload Lambda function."
  value       = aws_iam_role.complete_upload_lambda.arn
}

output "complete_template_upload_lambda_function_name" {
  description = "Lambda function name for the complete-template-upload handler."
  value       = aws_lambda_function.complete_upload.function_name
}

output "complete_template_upload_lambda_function_arn" {
  description = "Lambda function ARN for the complete-template-upload handler."
  value       = aws_lambda_function.complete_upload.arn
}

output "upload_http_api_id" {
  description = "HTTP API Gateway identifier for the upload flow."
  value       = aws_apigatewayv2_api.upload.id
}

output "upload_http_api_endpoint" {
  description = "Invoke URL for the upload HTTP API stage."
  value       = aws_apigatewayv2_stage.upload.invoke_url
}

# Temporarily disabled outputs related to custom domain / ACM / Route53.
#
# output "upload_http_api_custom_domain_name" {
#   description = "Custom domain name attached to the upload HTTP API when enabled."
#   value       = try(aws_apigatewayv2_domain_name.upload[0].domain_name, null)
# }
#
# output "upload_http_api_custom_domain_target" {
#   description = "Regional API Gateway target backing the custom domain alias when enabled."
#   value       = try(aws_apigatewayv2_domain_name.upload[0].domain_name_configuration[0].target_domain_name, null)
# }
#
# output "upload_http_api_certificate_arn" {
#   description = "ACM certificate ARN used by the upload HTTP API custom domain when enabled."
#   value       = try(aws_acm_certificate_validation.upload_http_api[0].certificate_arn, null)
# }

output "max_upload_size_bytes" {
  description = "Configured maximum upload size for the application contract."
  value       = var.max_upload_size_bytes
}

output "upload_alerts_topic_arn" {
  description = "SNS topic ARN for upload alert notifications."
  value       = aws_sns_topic.upload_alerts.arn
}
