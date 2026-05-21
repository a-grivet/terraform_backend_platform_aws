variable "aws_region" {
  description = "AWS region where the Terraform state backend resources are created."
  type        = string
  default     = "eu-west-3"
}

variable "backend_bucket_name" {
  description = "Optional explicit S3 bucket name for the shared Terraform remote backend."
  type        = string
  default     = null
}

variable "enable_versioning" {
  description = "Enable versioning on the Terraform state bucket."
  type        = bool
  default     = true
}

variable "encrypt_with_kms" {
  description = "Use KMS encryption instead of AES256 for the Terraform state bucket."
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

variable "tags" {
  description = "Tags applied to the Terraform state backend resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "state-backend"
  }
}
