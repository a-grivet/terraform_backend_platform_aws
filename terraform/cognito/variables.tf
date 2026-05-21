variable "aws_region" {
  description = "AWS region hosting the Cognito User Pool."
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
  default     = "dev"
}

variable "user_pool_name" {
  description = "Optional explicit Cognito User Pool name."
  type        = string
  default     = null
}

variable "user_pool_client_name" {
  description = "Optional explicit Cognito User Pool client name."
  type        = string
  default     = null
}

variable "password_minimum_length" {
  description = "Minimum password length for users."
  type        = number
  default     = 12
}

variable "temporary_password_validity_days" {
  description = "Number of days a temporary (admin-set) password is valid."
  type        = number
  default     = 7
}

variable "test_users" {
  description = "Map of test users to create. Each entry maps a username to sandbox role metadata."
  type = map(object({
    email              = string
    aws_account_id     = string
    role_name          = string
    cohort_id          = string
    temporary_password = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to Cognito resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "cognito"
  }
}
