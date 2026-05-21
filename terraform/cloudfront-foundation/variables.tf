variable "aws_region" {
  description = "Primary AWS region (eu-west-3). Used for remote state data sources."
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
}

variable "terraform_state_bucket" {
  description = "S3 bucket holding Terraform remote state for all stacks."
  type        = string
}

variable "upload_foundation_state_key" {
  description = "S3 key for the upload-foundation Terraform state."
  type        = string
  default     = "platform/upload-foundation/dev/terraform.tfstate"
}

variable "deployment_foundation_state_key" {
  description = "S3 key for the deployment-foundation Terraform state."
  type        = string
  default     = "platform/deployment-foundation/dev/terraform.tfstate"
}

variable "allowed_country_codes" {
  description = "ISO 3166-1 alpha-2 codes allowed through the WAF. All other origins are blocked."
  type        = list(string)
  default     = ["FR"]
}

variable "rate_limit_per_ip" {
  description = "Maximum requests per IP per 5-minute window before blocking."
  type        = number
  default     = 100
}

variable "ip_allowlist" {
  description = "CIDR ranges that bypass all WAF rules (CI runner IPs, admin). Leave empty to disable."
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "Retention period in days for WAF CloudWatch logs in us-east-1."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "cloudfront-foundation"
  }
}
