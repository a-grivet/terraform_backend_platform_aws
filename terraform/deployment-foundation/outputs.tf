output "aws_account_id" {
  description = "AWS account ID where the deployment foundation resources are created."
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_state_machine_arn" {
  description = "ARN of the Step Functions state machine that orchestrates deployment tasks."
  value       = aws_sfn_state_machine.deployment.arn
}

output "deployment_state_machine_name" {
  description = "Name of the Step Functions state machine."
  value       = aws_sfn_state_machine.deployment.name
}

output "deployment_api_endpoint" {
  description = "Invoke URL of the deployment HTTP API stage."
  value       = aws_apigatewayv2_stage.deployment.invoke_url
}

output "deployment_api_id" {
  description = "HTTP API Gateway identifier for the deployment API."
  value       = aws_apigatewayv2_api.deployment.id
}

output "trigger_deployment_lambda_function_name" {
  description = "Lambda function name for the trigger-deployment handler."
  value       = aws_lambda_function.trigger_deployment.function_name
}

output "trigger_deployment_lambda_function_arn" {
  description = "Lambda function ARN for the trigger-deployment handler."
  value       = aws_lambda_function.trigger_deployment.arn
}

output "trigger_deployment_lambda_role_arn" {
  description = "IAM role ARN for the trigger-deployment Lambda function."
  value       = aws_iam_role.trigger_lambda.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name where deployment runner tasks are launched."
  value       = aws_ecs_cluster.deployment.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN where deployment runner tasks are launched."
  value       = aws_ecs_cluster.deployment.arn
}

output "ecs_task_role_arn" {
  description = "IAM role ARN assumed by deployment runner ECS tasks — add this to learner-sandbox-roles deployer_role_arns."
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_task_role_name" {
  description = "IAM role name assumed by deployment runner ECS tasks."
  value       = aws_iam_role.ecs_task.name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN for the deployment runner."
  value       = aws_ecs_task_definition.deployment_runner.arn
}

output "deployment_alerts_topic_arn" {
  description = "SNS topic ARN for deployment alert notifications."
  value       = aws_sns_topic.deployment_alerts.arn
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID used by the deployment API for token validation."
  value       = try(data.terraform_remote_state.cognito.outputs.user_pool_id, "")
}

output "cognito_client_id" {
  description = "Cognito app client ID used by the deployment API for token validation."
  value       = try(data.terraform_remote_state.cognito.outputs.user_pool_client_id, "")
}
