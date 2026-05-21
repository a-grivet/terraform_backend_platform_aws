variable "aws_region" {
  description = "Region hosting validation foundation resources."
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name used in validation resource naming."
  type        = string
  default     = "dev"
}

variable "upload_bucket_name" {
  description = "Optional explicit S3 bucket name consumed by the validation flow."
  type        = string
  default     = null
}

variable "upload_intents_table_name" {
  description = "Optional explicit DynamoDB table name storing upload and validation statuses."
  type        = string
  default     = null
}

variable "ecs_cluster_name" {
  description = "Optional explicit ECS cluster name for validation tasks."
  type        = string
  default     = null
}

variable "ecs_task_family" {
  description = "Optional explicit ECS task definition family for validation tasks."
  type        = string
  default     = null
}

variable "validation_runner_image_repository" {
  description = "Optional ECR repository URI used for the validation runner image, without tag."
  type        = string
  default     = null
}

variable "validation_runner_image_tag" {
  description = "Immutable Git commit SHA tag used by the validation runner image."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_validation_runtime || (var.validation_runner_image_tag != null && can(regex("^[0-9a-f]{40}$", var.validation_runner_image_tag)))
    error_message = "validation_runner_image_tag must be a 40-character lowercase Git commit SHA when enable_validation_runtime is true."
  }
}

variable "event_rule_name" {
  description = "Optional explicit EventBridge rule name for pending blueprint validation triggers."
  type        = string
  default     = null
}

variable "event_bus_name" {
  description = "EventBridge bus name used for pending blueprint validation events."
  type        = string
  default     = "default"
}

variable "raw_upload_key_prefix" {
  description = "S3 key prefix used to identify pending uploaded ZIP packages."
  type        = string
  default     = "blueprints/pending/"
}

variable "enable_validation_runtime" {
  description = "Create ECS, IAM, and EventBridge target resources for the validation flow."
  type        = bool
  default     = false
}

variable "enable_validation_trigger" {
  description = "Enable the EventBridge rule once the validation runner is ready to process real uploads."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_validation_trigger || var.enable_validation_runtime
    error_message = "enable_validation_trigger cannot be true when enable_validation_runtime is false."
  }
}

variable "task_cpu" {
  description = "CPU units allocated to the validation runner task."
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Memory in MiB allocated to the validation runner task."
  type        = number
  default     = 2048
}

variable "create_validation_network" {
  description = "Create a dedicated private VPC, private subnets, route tables, and security groups for the validation runtime."
  type        = bool
  default     = false
}

variable "validation_vpc_cidr_block" {
  description = "CIDR block used when create_validation_network is true."
  type        = string
  default     = "10.42.0.0/16"
}

variable "validation_private_subnet_cidrs" {
  description = "Private subnet CIDR blocks created when create_validation_network is true."
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24"]

  validation {
    condition     = !var.create_validation_network || length(var.validation_private_subnet_cidrs) >= 2
    error_message = "validation_private_subnet_cidrs must contain at least two private subnet CIDRs when create_validation_network is true."
  }
}

variable "validation_availability_zones" {
  description = "Optional availability zones used when create_validation_network is true. Defaults to the first zones returned by AWS."
  type        = list(string)
  default     = []
}

# When this stack is integrated into an existing platform, these identifiers
# should be adapted to the target VPC and subnet layout rather than recreated.
variable "subnet_ids" {
  description = "Subnet IDs used by validation tasks."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_validation_runtime || var.create_validation_network || length(var.subnet_ids) > 0
    error_message = "subnet_ids must be provided when enable_validation_runtime is true unless create_validation_network is enabled."
  }
}

# When this stack is integrated into an existing platform, these identifiers
# should be adapted to the target VPC and subnet layout rather than recreated.
variable "security_group_ids" {
  description = "Security group IDs attached to validation tasks."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_validation_runtime || var.create_validation_network || length(var.security_group_ids) > 0
    error_message = "security_group_ids must be provided when enable_validation_runtime is true unless create_validation_network is enabled."
  }
}

variable "assign_public_ip" {
  description = "Whether validation tasks should be launched with a public IP."
  type        = bool
  default     = false
}

variable "manage_private_service_endpoints" {
  description = "Create the private VPC endpoints required by the validation runner runtime."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID hosting the private subnets used by the validation runner and its endpoints."
  type        = string
  default     = null

  validation {
    condition     = !var.manage_private_service_endpoints || var.create_validation_network || var.vpc_id != null
    error_message = "vpc_id must be provided when manage_private_service_endpoints is true unless create_validation_network is enabled."
  }
}

# When this stack is integrated into an existing platform, these identifiers
# should be adapted to the target VPC and subnet layout rather than recreated.
variable "private_route_table_ids" {
  description = "Route table IDs attached to the private subnets used by the validation runner."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.manage_private_service_endpoints || var.create_validation_network || length(var.private_route_table_ids) > 0
    error_message = "private_route_table_ids must be provided when manage_private_service_endpoints is true unless create_validation_network is enabled."
  }
}

# When this stack is integrated into an existing platform, these identifiers
# should be adapted to the target VPC and subnet layout rather than recreated.
variable "interface_endpoint_subnet_ids" {
  description = "Optional explicit subnet IDs used by interface VPC endpoints. Defaults to subnet_ids when omitted."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.manage_private_service_endpoints || var.create_validation_network || length(var.interface_endpoint_subnet_ids) > 0 || length(var.subnet_ids) > 0
    error_message = "interface_endpoint_subnet_ids or subnet_ids must be provided when manage_private_service_endpoints is true unless create_validation_network is enabled."
  }
}

variable "cloudwatch_log_group_name" {
  description = "Optional explicit CloudWatch Logs group name for validation runner tasks."
  type        = string
  default     = null
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention in days for validation runner log groups."
  type        = number
  default     = 365
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs when using an existing validation VPC. Dedicated validation VPCs always enable Flow Logs."
  type        = bool
  default     = false

  validation {
    condition     = var.create_validation_network || !var.enable_vpc_flow_logs || var.vpc_id != null
    error_message = "vpc_id must be provided when enable_vpc_flow_logs is true unless create_validation_network is enabled."
  }
}

variable "vpc_flow_logs_log_group_name" {
  description = "Optional explicit CloudWatch Logs group name for validation VPC Flow Logs."
  type        = string
  default     = null
}

variable "vpc_flow_logs_retention_days" {
  description = "CloudWatch Logs retention in days for validation VPC Flow Logs."
  type        = number
  default     = 90
}

variable "vpc_flow_logs_traffic_type" {
  description = "Traffic type captured by validation VPC Flow Logs."
  type        = string
  default     = "REJECT"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.vpc_flow_logs_traffic_type)
    error_message = "vpc_flow_logs_traffic_type must be one of ACCEPT, REJECT, or ALL."
  }
}

variable "alert_email" {
  description = "Email address for validation alert notifications via SNS. Leave null to skip email subscription."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to validation foundation resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "validation-foundation"
  }
}
