provider "aws" {
  region = var.aws_region
}

locals {
  user_pool_name        = coalesce(var.user_pool_name, "inca-learners-${var.environment}")
  user_pool_client_name = coalesce(var.user_pool_client_name, "inca-deployment-api-${var.environment}")
  common_tags           = merge(var.tags, { environment = var.environment })
  waf_web_acl_arn       = try(data.terraform_remote_state.waf.outputs.web_acl_arn, "")
}

resource "aws_cognito_user_pool" "learners" {
  name = local.user_pool_name

  # Usernames are immutable after creation; email is the login identifier.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = var.temporary_password_validity_days
  }

  # Custom attributes that the deployment API reads to know which AWS account
  # and IAM role to assume when running Terraform for this learner.
  schema {
    name                = "aws_account_id"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 12
      max_length = 12
    }
  }

  schema {
    name                = "role_name"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 1
      max_length = 128
    }
  }

  schema {
    name                = "cohort_id"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }

  # Standard email schema — override to make it required.
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = local.common_tags
}

# App client used by the deployment API backend (no client secret — machine-to-machine via SRP).
resource "aws_cognito_user_pool_client" "deployment_api" {
  name         = local.user_pool_client_name
  user_pool_id = aws_cognito_user_pool.learners.id

  # The deployment API validates JWT tokens server-side — no hosted UI needed.
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # Tokens must be short-lived; the API re-reads pool attributes on every call.
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Do not generate a client secret — the client is a server-side API.
  generate_secret = false

  # Read claims needed by the deployment API.
  read_attributes = [
    "email",
    "custom:aws_account_id",
    "custom:role_name",
    "custom:cohort_id"
  ]

  write_attributes = [
    "email",
    "custom:aws_account_id",
    "custom:role_name",
    "custom:cohort_id"
  ]
}

# Test users — created only when var.test_users is populated.
resource "aws_cognito_user" "test" {
  for_each = var.test_users

  user_pool_id = aws_cognito_user_pool.learners.id
  username     = each.key

  attributes = {
    email                   = each.value.email
    email_verified          = "true"
    "custom:aws_account_id" = each.value.aws_account_id
    "custom:role_name"      = each.value.role_name
    "custom:cohort_id"      = each.value.cohort_id
  }

  temporary_password   = each.value.temporary_password
  message_action       = "SUPPRESS"
  force_alias_creation = false
}

# ---------------------------------------------------------------------------
# WAF — read current ARN from the waf-foundation remote state so it stays
# in sync even if the Web ACL is destroyed and recreated (which changes its ID).
# ---------------------------------------------------------------------------

data "terraform_remote_state" "waf" {
  backend = "s3"
  config = {
    bucket = "inca-terraform-state-066122607629"
    key    = "platform/waf-foundation/${var.environment}/terraform.tfstate"
    region = var.aws_region
  }
}

resource "aws_wafv2_web_acl_association" "cognito" {
  count        = local.waf_web_acl_arn != "" ? 1 : 0
  resource_arn = aws_cognito_user_pool.learners.arn
  web_acl_arn  = local.waf_web_acl_arn
}
