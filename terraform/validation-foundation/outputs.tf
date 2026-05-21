output "upload_bucket_name" {
  description = "Terraform blueprint lifecycle bucket consumed by the validation flow."
  value       = local.upload_bucket_name
}

output "upload_intents_table_name" {
  description = "DynamoDB table storing upload and validation statuses."
  value       = local.upload_intents_table_name
}

output "validation_ecs_cluster_name" {
  description = "Derived ECS cluster name for validation tasks."
  value       = local.ecs_cluster_name
}

output "validation_ecs_task_family" {
  description = "Derived ECS task definition family for validation tasks."
  value       = local.ecs_task_family
}

output "validation_event_rule_name" {
  description = "Derived EventBridge rule name for pending blueprint validation triggers."
  value       = aws_cloudwatch_event_rule.validation_upload_trigger.name
}

output "validation_event_rule_arn" {
  description = "EventBridge rule ARN filtering pending blueprint events for validation."
  value       = aws_cloudwatch_event_rule.validation_upload_trigger.arn
}

output "validation_event_bus_name" {
  description = "EventBridge bus used by the validation upload trigger."
  value       = aws_cloudwatch_event_rule.validation_upload_trigger.event_bus_name
}

output "validation_upload_event_pattern" {
  description = "Event pattern used to capture pending uploaded ZIP packages."
  value       = local.validation_upload_event_pattern
}

output "validation_cloudwatch_log_group_name" {
  description = "Derived CloudWatch Logs group name for validation runner tasks."
  value       = local.cloudwatch_log_group_name
}

output "validation_vpc_flow_logs_enabled" {
  description = "Whether VPC Flow Logs are enabled for the validation VPC."
  value       = local.manage_vpc_flow_logs
}

output "validation_vpc_flow_logs_id" {
  description = "VPC Flow Logs resource ID when enabled."
  value       = try(aws_flow_log.validation_vpc[0].id, aws_flow_log.existing_vpc[0].id, null)
}

output "validation_vpc_flow_logs_log_group_name" {
  description = "CloudWatch Logs group name receiving validation VPC Flow Logs."
  value       = local.manage_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}

output "validation_vpc_flow_logs_traffic_type" {
  description = "Traffic type captured by validation VPC Flow Logs."
  value       = var.vpc_flow_logs_traffic_type
}

output "validation_runtime_enabled" {
  description = "Whether ECS runtime resources are enabled for the validation flow."
  value       = var.enable_validation_runtime
}

output "validation_trigger_enabled" {
  description = "Whether the EventBridge rule is enabled to trigger real validation tasks."
  value       = var.enable_validation_trigger
}

output "validation_ecs_cluster_arn" {
  description = "ECS cluster ARN for validation tasks when runtime resources are enabled."
  value       = var.enable_validation_runtime ? aws_ecs_cluster.validation[0].arn : null
}

output "validation_task_definition_arn" {
  description = "Task definition ARN for the validation runner when runtime resources are enabled."
  value       = var.enable_validation_runtime ? aws_ecs_task_definition.validation_runner[0].arn : null
}

output "validation_task_role_arn" {
  description = "Task role ARN used by the validation runner when runtime resources are enabled."
  value       = var.enable_validation_runtime ? aws_iam_role.validation_task[0].arn : null
}

output "validation_execution_role_arn" {
  description = "Execution role ARN used by the validation runner when runtime resources are enabled."
  value       = var.enable_validation_runtime ? aws_iam_role.validation_task_execution[0].arn : null
}

output "validation_network_created" {
  description = "Whether the validation stack creates its own VPC, private subnets, and task security group."
  value       = var.create_validation_network
}

output "validation_vpc_id" {
  description = "VPC ID used by the validation runtime and private service endpoints."
  value       = local.effective_vpc_id
}

output "validation_private_subnet_ids" {
  description = "Private subnet IDs used by the validation runtime."
  value       = local.effective_subnet_ids
}

output "validation_task_security_group_ids" {
  description = "Security group IDs attached to the validation runtime tasks."
  value       = local.effective_task_security_group_ids
}

output "validation_private_service_endpoints_enabled" {
  description = "Whether validation VPC endpoints are managed by this stack."
  value       = var.manage_private_service_endpoints
}

output "validation_private_service_endpoint_security_group_id" {
  description = "Security group attached to interface endpoints when private service endpoints are enabled."
  value       = var.manage_private_service_endpoints ? aws_security_group.private_service_endpoints[0].id : null
}

output "validation_s3_vpc_endpoint_id" {
  description = "Gateway VPC endpoint ID for S3 when private service endpoints are enabled."
  value       = var.manage_private_service_endpoints ? aws_vpc_endpoint.s3[0].id : null
}

output "validation_dynamodb_vpc_endpoint_id" {
  description = "Gateway VPC endpoint ID for DynamoDB when private service endpoints are enabled."
  value       = var.manage_private_service_endpoints ? aws_vpc_endpoint.dynamodb[0].id : null
}

output "validation_ecr_api_vpc_endpoint_id" {
  description = "Interface VPC endpoint ID for ECR API when private service endpoints are enabled."
  value       = var.manage_private_service_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
}

output "validation_ecr_dkr_vpc_endpoint_id" {
  description = "Interface VPC endpoint ID for ECR Docker registry when private service endpoints are enabled."
  value       = var.manage_private_service_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
}

output "validation_logs_vpc_endpoint_id" {
  description = "Interface VPC endpoint ID for CloudWatch Logs when private service endpoints are enabled."
  value       = var.manage_private_service_endpoints ? aws_vpc_endpoint.logs[0].id : null
}

output "validation_sts_vpc_endpoint_id" {
  description = "Interface VPC endpoint ID for STS when private service endpoints are enabled."
  value       = var.manage_private_service_endpoints ? aws_vpc_endpoint.sts[0].id : null
}

output "validation_alerts_topic_arn" {
  description = "SNS topic ARN for validation alert notifications."
  value       = aws_sns_topic.validation_alerts.arn
}
