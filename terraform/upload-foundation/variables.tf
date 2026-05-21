variable "aws_region" {
  description = "region hosting the upload foundation resources."
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
  default     = "dev"
}

variable "upload_bucket_name" {
  description = "Optional explicit S3 bucket name for Terraform blueprint lifecycle objects."
  type        = string
  default     = null
}

variable "upload_bucket_region" {
  description = "Region used to create regional S3 presigned URLs. Defaults to aws_region."
  type        = string
  default     = null
}

variable "dynamodb_table_name" {
  description = "Optional explicit DynamoDB table name storing upload intents. Defaults to a legacy-compatible dev name or an environment-suffixed name."
  type        = string
  default     = null
}

variable "lambda_role_name" {
  description = "Optional explicit IAM role name for the prepare-template-upload Lambda function."
  type        = string
  default     = null
}

variable "lambda_policy_name" {
  description = "Optional explicit IAM policy name attached to the prepare-template-upload Lambda role."
  type        = string
  default     = null
}

variable "lambda_function_name" {
  description = "Optional explicit Lambda function name for the prepare-template-upload handler."
  type        = string
  default     = null
}

variable "complete_lambda_role_name" {
  description = "Optional explicit IAM role name for the complete-template-upload Lambda function."
  type        = string
  default     = null
}

variable "complete_lambda_policy_name" {
  description = "Optional explicit IAM policy name attached to the complete-template-upload Lambda role."
  type        = string
  default     = null
}

variable "complete_lambda_function_name" {
  description = "Optional explicit Lambda function name for the complete-template-upload handler."
  type        = string
  default     = null
}

variable "lambda_runtime" {
  description = "Lambda runtime for the prepare-template-upload function."
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Handler entrypoint for the prepare-template-upload Lambda."
  type        = string
  default     = "handler.lambda_handler"
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds for the prepare-template-upload function."
  type        = number
  default     = 10
}

variable "lambda_memory_size_mb" {
  description = "Lambda memory size in MB for the prepare-template-upload function."
  type        = number
  default     = 256
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Logs retention in days for upload Lambda log groups."
  type        = number
  default     = 30
}

variable "presigned_url_expiration_seconds" {
  description = "Presigned PUT URL expiration returned by the prepare-template-upload Lambda."
  type        = number
  default     = 900
}

variable "http_api_name" {
  description = "Optional explicit API Gateway HTTP API name for the upload flow."
  type        = string
  default     = null
}

variable "http_api_stage_name" {
  description = "API Gateway stage name for the upload flow."
  type        = string
  default     = "$default"
}

variable "http_api_throttling_burst_limit" {
  description = "API Gateway HTTP API default burst throttling limit for upload routes."
  type        = number
  default     = 50
}

variable "http_api_throttling_rate_limit" {
  description = "API Gateway HTTP API default steady-state throttling rate limit for upload routes."
  type        = number
  default     = 100
}

# tflint-ignore: terraform_unused_declarations
variable "http_api_custom_domain_name" {
  description = "Optional custom domain name for the upload HTTP API, for example api.accounts.revolve.training."
  type        = string
  default     = null
}

# tflint-ignore: terraform_unused_declarations
variable "hosted_zone_id" {
  description = "Route53 hosted zone ID used to validate the ACM certificate and publish the API custom domain alias."
  type        = string
  default     = null
}

# tflint-ignore: terraform_unused_declarations
variable "api_allowed_cors_origins" {
  description = "Allowed CORS origins for browser calls to the upload HTTP API. Leave empty to disable API Gateway CORS."
  type        = list(string)
  default     = []
}

# tflint-ignore: terraform_unused_declarations
variable "api_allowed_cors_methods" {
  description = "Allowed CORS methods for the upload HTTP API."
  type        = list(string)
  default     = ["POST"]
}

# tflint-ignore: terraform_unused_declarations
variable "api_allowed_cors_headers" {
  description = "Allowed CORS headers for the upload HTTP API."
  type        = list(string)
  default     = ["Content-Type", "Authorization"]
}

# tflint-ignore: terraform_unused_declarations
variable "api_allow_credentials" {
  description = "Whether the upload HTTP API should allow browser credentials in CORS responses."
  type        = bool
  default     = false
}

# tflint-ignore: terraform_unused_declarations
variable "api_cors_max_age_seconds" {
  description = "Max age in seconds for cached CORS preflight responses on the upload HTTP API."
  type        = number
  default     = 300
}

variable "enable_versioning" {
  description = "Enable versioning on the upload bucket."
  type        = bool
  default     = false
}

variable "encrypt_with_kms" {
  description = "Use KMS encryption for the upload bucket and DynamoDB table."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN used when encrypt_with_kms is true."
  type        = string
  default     = null

  validation {
    condition     = !var.encrypt_with_kms || var.kms_key_arn != null
    error_message = "kms_key_arn must be provided when encrypt_with_kms is true."
  }
}

variable "allowed_cors_origins" {
  description = "Allowed CORS origins for direct browser uploads to the presigned S3 bucket."
  type        = list(string)
  default     = ["*"]
}

variable "max_upload_size_bytes" {
  description = "Maximum upload size accepted by the application contract."
  type        = number
  default     = 20971520
}

variable "alert_email" {
  description = "Email address for upload alert notifications via SNS. Leave null to skip email subscription."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to upload foundation resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "upload-foundation"
  }
}
