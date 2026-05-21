variable "aws_region" {
  description = "AWS region hosting deployment foundation resources."
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
  default     = "dev"
}

variable "upload_bucket_name" {
  description = "Optional explicit S3 bucket name storing validated blueprints."
  type        = string
  default     = null
}

variable "upload_intents_table_name" {
  description = "Optional explicit DynamoDB table name storing upload and deployment statuses."
  type        = string
  default     = null
}

variable "state_machine_name" {
  description = "Optional explicit Step Functions state machine name."
  type        = string
  default     = null
}

variable "deployment_runner_image_repository" {
  description = "ECR repository URI for the deployment runner image, without tag."
  type        = string
  default     = null
}

variable "deployment_runner_image_tag" {
  description = "Immutable Git commit SHA tag used by the deployment runner image."
  type        = string
  default     = null

  validation {
    condition     = var.deployment_runner_image_tag == null || can(regex("^[0-9a-f]{40}$", var.deployment_runner_image_tag))
    error_message = "deployment_runner_image_tag must be a 40-character lowercase Git commit SHA."
  }
}

variable "ecs_cluster_name" {
  description = "ECS cluster name where deployment runner tasks are launched."
  type        = string
  default     = null
}

variable "ecs_task_family" {
  description = "Optional explicit ECS task definition family for deployment runner tasks."
  type        = string
  default     = null
}

variable "assign_public_ip" {
  description = "Whether deployment runner tasks should be launched with a public IP."
  type        = bool
  default     = false
}

variable "task_cpu" {
  description = "CPU units allocated to the deployment runner task."
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Memory in MiB allocated to the deployment runner task."
  type        = number
  default     = 2048
}

variable "cloudwatch_log_group_name" {
  description = "Optional explicit CloudWatch Logs group name for deployment runner tasks."
  type        = string
  default     = null
}

variable "api_gateway_name" {
  description = "Optional explicit API Gateway name for the deployment API."
  type        = string
  default     = null
}

variable "alert_email" {
  description = "Email address for deployment alert notifications via SNS. Leave null to skip email subscription."
  type        = string
  default     = null
}

variable "http_api_stage_name" {
  description = "API Gateway HTTP API stage name. Use a non-$ name to enable WAF association."
  type        = string
  default     = "api"
}

variable "tags" {
  description = "Tags applied to deployment foundation resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "deployment-foundation"
  }
}
