output "user_pool_id" {
  description = "Cognito User Pool ID."
  value       = aws_cognito_user_pool.learners.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN."
  value       = aws_cognito_user_pool.learners.arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint (without https://)."
  value       = aws_cognito_user_pool.learners.endpoint
}

output "user_pool_client_id" {
  description = "Cognito User Pool client ID used by the deployment API."
  value       = aws_cognito_user_pool_client.deployment_api.id
}
