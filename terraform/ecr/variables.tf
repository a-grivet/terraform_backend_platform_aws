variable "aws_region" {
  description = "AWS region hosting the ECR repository."
  type        = string
  default     = "eu-west-3"
}

variable "repository_name" {
  description = "Name of the ECR repository used for the Terraform runner image."
  type        = string
  default     = "inca-terraform-runner"
}

variable "image_tag_mutability" {
  description = "Image tag mutability mode for the repository."
  type        = string
  default     = "IMMUTABLE_WITH_EXCLUSION"

  validation {
    condition = contains([
      "MUTABLE",
      "IMMUTABLE",
      "MUTABLE_WITH_EXCLUSION",
      "IMMUTABLE_WITH_EXCLUSION",
    ], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE, IMMUTABLE, MUTABLE_WITH_EXCLUSION, or IMMUTABLE_WITH_EXCLUSION."
  }
}

variable "image_tag_mutability_exclusion_filters" {
  description = "Wildcard filters for tags excluded from the configured image tag mutability mode."
  type = list(object({
    filter_type = string
    filter      = string
  }))
  default = [
    {
      filter_type = "WILDCARD"
      filter      = "dev"
    },
    {
      filter_type = "WILDCARD"
      filter      = "main"
    },
    {
      filter_type = "WILDCARD"
      filter      = "latest"
    },
  ]

  validation {
    condition = alltrue([
      for exclusion_filter in var.image_tag_mutability_exclusion_filters :
      exclusion_filter.filter_type == "WILDCARD"
    ])
    error_message = "Only WILDCARD image tag mutability exclusion filters are supported."
  }
}

variable "scan_on_push" {
  description = "Enable ECR scan on push."
  type        = bool
  default     = true
}

variable "encrypt_with_kms" {
  description = "Use KMS encryption instead of AES256."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN used when encrypt_with_kms is true."
  type        = string
  default     = null
}

variable "allowed_push_role_arns" {
  description = "Optional list of IAM role ARNs allowed to push images."
  type        = list(string)
  default     = []
}

variable "allowed_pull_role_arns" {
  description = "Optional list of IAM role ARNs allowed to pull images."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to ECR resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
  }
}
