variable "aws_region" {
  description = <<-EOT
    AWS region where this IAM/OIDC stack is applied.

    Important:
    - this stack must be applied in the same AWS account that hosts the GitLab-assumable IAM roles
    - in most cases, this should also be the same region as the target ECR repository

    Example for a personal test account:
    aws_region = "eu-west-3"

    Example for the future management account:
    aws_region = "eu-west-1"
  EOT
  type        = string
  default     = "eu-west-1"
}

variable "gitlab_domain" {
  description = <<-EOT
    GitLab domain used as the OIDC issuer.

    This must match:
    - the GitLab instance issuing the CI job token
    - the OIDC provider URL configured in AWS

    In the current INCA ecosystem, the expected value is usually:
    gitlab_domain = "gitlab.revolve.team"
  EOT
  type        = string
  default     = "gitlab.revolve.team"
}

variable "gitlab_audience" {
  description = <<-EOT
    OIDC audience expected by AWS IAM for the GitLab-issued token.

    This value must match the `aud` configured in `.gitlab-ci.yml` under `id_tokens`.

    Example:
    gitlab_audience = "https://gitlab.revolve.team"
  EOT
  type        = string
  default     = "https://gitlab.revolve.team"
}

variable "gitlab_thumbprint" {
  description = <<-EOT
    Thumbprint used when creating the AWS IAM OIDC provider.

    This is only used when `create_oidc_provider = true`.
    It should be reviewed before production use because certificate chains can evolve over time.

    The default value comes from the existing INCA organization Terraform codebase.
  EOT
  type        = string
  default     = "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
}

variable "create_oidc_provider" {
  description = <<-EOT
    Controls whether this stack creates the AWS IAM OIDC provider.

    Use `true` when the target account does not yet contain a provider for the GitLab domain.
    Use `false` when the provider already exists in the target account and should be reused.

    Migration guidance:
    - personal AWS test account with no provider yet -> true
    - management account where a shared provider already exists -> false
  EOT
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = <<-EOT
    ARN of an already existing AWS IAM OIDC provider.

    This variable is only required when:
    - `create_oidc_provider = false`

    Leave it as null when the provider is created by this stack.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != null
    error_message = "existing_oidc_provider_arn must be provided when create_oidc_provider is false."
  }
}

variable "gitlab_project_path" {
  description = <<-EOT
    GitLab project path allowed to assume the AWS IAM role.

    This is one of the most important variables because it scopes the trust policy to a repository.

    Example:
    gitlab_project_path = "inca/inca-auto-deployer"

    You can also use a wildcard pattern if the governance model requires it,
    but a precise repository path is strongly recommended.
  EOT
  type        = string
}

variable "gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy.

    Each entry is transformed into a GitLab OIDC `sub` pattern such as:
    project_path:<project_path>:ref_type:branch:ref:<branch_pattern>

    Examples:
    - ["main"]
    - ["main", "release/*"]
    - ["feature/oidc-test"] for a temporary bootstrap test

    This variable is the main lever used to move from a test setup to the future management account setup
    without changing the Terraform logic.
  EOT
  type        = list(string)
  default     = ["main"]

  validation {
    condition     = length(var.gitlab_branch_patterns) > 0
    error_message = "gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "iam_role_name" {
  description = <<-EOT
    Name of the IAM role that GitLab CI will assume through OIDC for runner image publication.

    This role should be dedicated to this repository or at least to this delivery use case.

    Example:
    iam_role_name = "inca-auto-deployer-gitlab-ecr-push"
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-ecr-push"
}

variable "iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the runner/ECR role.

    The default value is intentionally specific to the ECR push responsibility.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-ecr-push"
}

variable "upload_dev_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the upload foundation dev deployment role.

    This should usually target the development branch used to test the upload infrastructure CI/CD.

    Example:
    upload_dev_gitlab_branch_patterns = ["dev"]
  EOT
  type        = list(string)
  default     = ["dev"]

  validation {
    condition     = length(var.upload_dev_gitlab_branch_patterns) > 0
    error_message = "upload_dev_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "upload_dev_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the upload foundation on the dev branch.

    Example:
    upload_dev_iam_role_name = "inca-auto-deployer-gitlab-upload-dev"
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-upload-dev"
}

variable "upload_dev_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the upload foundation dev deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-upload-dev"
}

variable "upload_main_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the upload foundation main deployment role.

    This should usually target the protected production branch used to deploy the upload infrastructure.

    Example:
    upload_main_gitlab_branch_patterns = ["main"]
  EOT
  type        = list(string)
  default     = ["main", "master"]

  validation {
    condition     = length(var.upload_main_gitlab_branch_patterns) > 0
    error_message = "upload_main_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "upload_main_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the upload foundation on the main branch.

    Example:
    upload_main_iam_role_name = "inca-auto-deployer-gitlab-upload-main"
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-upload-main"
}

variable "upload_main_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the upload foundation main deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-upload-main"
}

variable "validation_dev_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the validation foundation dev deployment role.

    This should usually target the development branch used to test the validation infrastructure CI/CD.
  EOT
  type        = list(string)
  default     = ["dev"]

  validation {
    condition     = length(var.validation_dev_gitlab_branch_patterns) > 0
    error_message = "validation_dev_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "validation_dev_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the validation foundation on the dev branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-validation-dev"
}

variable "validation_dev_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the validation foundation dev deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-validation-dev"
}

variable "validation_main_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the validation foundation main deployment role.

    This should usually target the protected production branch used to deploy the validation infrastructure.
  EOT
  type        = list(string)
  default     = ["main", "master"]

  validation {
    condition     = length(var.validation_main_gitlab_branch_patterns) > 0
    error_message = "validation_main_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "validation_main_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the validation foundation on the main branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-validation-main"
}

variable "validation_main_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the validation foundation main deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-validation-main"
}

variable "gitlab_oidc_admin_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the GitLab OIDC / IAM foundation admin role.

    This role manages the centralized IAM/OIDC stack itself and is therefore
    expected to be assumable only from the integration branch and the mainline branches.
  EOT
  type        = list(string)
  default     = ["dev", "main", "master"]

  validation {
    condition     = length(var.gitlab_oidc_admin_gitlab_branch_patterns) > 0
    error_message = "gitlab_oidc_admin_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "gitlab_oidc_admin_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the centralized GitLab OIDC / IAM foundation stack.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-oidc-admin"
}

variable "gitlab_oidc_admin_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the centralized GitLab OIDC / IAM foundation admin role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-oidc-admin"
}

variable "terraform_state_backend_bucket_name" {
  description = <<-EOT
    Name of the shared S3 bucket used as the Terraform remote backend.

    This bucket stores the state files and lockfiles accessed by GitLab CI when
    planning or applying infrastructure changes.
  EOT
  type        = string
  default     = null
}

variable "upload_dev_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the upload foundation dev Terraform state in the shared backend bucket.

    This prefix is used to scope access to both the state object and the `.tflock`
    lockfile created when `use_lockfile = true`.
  EOT
  type        = string
  default     = "platform/upload-foundation/dev/*"
}

variable "upload_main_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the upload foundation main Terraform state in the shared backend bucket.

    This prefix is used to scope access to both the state object and the `.tflock`
    lockfile created when `use_lockfile = true`.
  EOT
  type        = string
  default     = "platform/upload-foundation/main/*"
}

variable "validation_dev_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the validation foundation dev Terraform state in the shared backend bucket.

    This prefix is used to scope access to both the state object and the `.tflock`
    lockfile created when `use_lockfile = true`.
  EOT
  type        = string
  default     = "platform/validation-foundation/dev/*"
}

variable "validation_main_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the validation foundation main Terraform state in the shared backend bucket.

    This prefix is used to scope access to both the state object and the `.tflock`
    lockfile created when `use_lockfile = true`.
  EOT
  type        = string
  default     = "platform/validation-foundation/main/*"
}

variable "gitlab_oidc_roles_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the centralized GitLab OIDC / IAM foundation Terraform state in the shared backend bucket.

    This prefix is used to scope access to both the state object and the `.tflock`
    lockfile created when `use_lockfile = true`.
  EOT
  type        = string
  default     = "platform/gitlab-oidc-roles/shared/*"
}

variable "ecr_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the ECR Terraform state in the shared backend bucket.

    This prefix is used to scope access to both the state object and the `.tflock`
    lockfile created when `use_lockfile = true`.
  EOT
  type        = string
  default     = "platform/ecr/shared/*"
}

variable "learner_sandbox_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the learner-sandbox-roles Terraform state in the shared backend bucket.
    Covers both dev and main environments since a single shared role deploys both.
  EOT
  type        = string
  default     = "platform/learner-sandbox-roles/*"
}

variable "cognito_dev_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the Cognito dev Terraform state in the shared backend bucket.
  EOT
  type        = string
  default     = "platform/cognito/dev/*"
}

variable "learner_sandbox_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the learner-sandbox-roles deployment role.
    A single shared role is used for both dev and main environments.
  EOT
  type        = list(string)
  default     = ["dev", "main", "master"]

  validation {
    condition     = length(var.learner_sandbox_gitlab_branch_patterns) > 0
    error_message = "learner_sandbox_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "learner_sandbox_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the learner sandbox roles stack.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-learner-sandbox"
}

variable "learner_sandbox_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the learner sandbox deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-learner-sandbox"
}

variable "cognito_dev_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the Cognito dev deployment role.
  EOT
  type        = list(string)
  default     = ["dev"]

  validation {
    condition     = length(var.cognito_dev_gitlab_branch_patterns) > 0
    error_message = "cognito_dev_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "cognito_dev_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the Cognito stack on the dev branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cognito-dev"
}

variable "cognito_dev_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the Cognito dev deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cognito-dev"
}

variable "deployment_dev_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the deployment-foundation dev Terraform state in the shared backend bucket.

    This prefix is used to scope access to both the state object and the `.tflock`
    lockfile created when `use_lockfile = true`.
  EOT
  type        = string
  default     = "platform/deployment-foundation/dev/*"
}

variable "deployment_dev_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the deployment-foundation dev deployment role.
  EOT
  type        = list(string)
  default     = ["dev"]

  validation {
    condition     = length(var.deployment_dev_gitlab_branch_patterns) > 0
    error_message = "deployment_dev_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "deployment_dev_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the deployment foundation on the dev branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-deployment-dev"
}

variable "deployment_dev_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the deployment foundation dev deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-deployment-dev"
}

variable "repository_name" {
  description = <<-EOT
    Name of the ECR repository that the runner publication role is allowed to push to.

    This value should match the ECR repository created by the `terraform/ecr` stack.
  EOT
  type        = string
  default     = "inca-terraform-runner"
}

variable "waf_dev_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the WAF foundation dev Terraform state in the shared backend bucket.
  EOT
  type        = string
  default     = "platform/waf-foundation/dev/*"
}

variable "waf_dev_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the WAF foundation dev deployment role.
  EOT
  type        = list(string)
  default     = ["dev"]

  validation {
    condition     = length(var.waf_dev_gitlab_branch_patterns) > 0
    error_message = "waf_dev_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "waf_dev_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the WAF foundation on the dev branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-waf-dev"
}

variable "waf_dev_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the WAF foundation dev deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-waf-dev"
}

variable "cloudfront_dev_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the cloudfront-foundation dev Terraform state in the shared backend bucket.
  EOT
  type        = string
  default     = "platform/cloudfront-foundation/dev/*"
}

variable "cloudfront_dev_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the cloudfront-foundation dev deployment role.
  EOT
  type        = list(string)
  default     = ["dev"]

  validation {
    condition     = length(var.cloudfront_dev_gitlab_branch_patterns) > 0
    error_message = "cloudfront_dev_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "cloudfront_dev_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the cloudfront-foundation on the dev branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cloudfront-dev"
}

variable "cloudfront_dev_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the cloudfront-foundation dev deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cloudfront-dev"
}

variable "deployment_main_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the deployment-foundation main Terraform state in the shared backend bucket.
  EOT
  type        = string
  default     = "platform/deployment-foundation/main/*"
}

variable "deployment_main_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the deployment-foundation main deployment role.
  EOT
  type        = list(string)
  default     = ["main", "master"]

  validation {
    condition     = length(var.deployment_main_gitlab_branch_patterns) > 0
    error_message = "deployment_main_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "deployment_main_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the deployment foundation on the main branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-deployment-main"
}

variable "deployment_main_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the deployment foundation main deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-deployment-main"
}

variable "cognito_main_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the Cognito main Terraform state in the shared backend bucket.
  EOT
  type        = string
  default     = "platform/cognito/main/*"
}

variable "cognito_main_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the Cognito main deployment role.
  EOT
  type        = list(string)
  default     = ["main", "master"]

  validation {
    condition     = length(var.cognito_main_gitlab_branch_patterns) > 0
    error_message = "cognito_main_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "cognito_main_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the Cognito stack on the main branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cognito-main"
}

variable "cognito_main_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the Cognito main deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cognito-main"
}

variable "waf_main_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the WAF foundation main Terraform state in the shared backend bucket.
  EOT
  type        = string
  default     = "platform/waf-foundation/main/*"
}

variable "waf_main_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the WAF foundation main deployment role.
  EOT
  type        = list(string)
  default     = ["main", "master"]

  validation {
    condition     = length(var.waf_main_gitlab_branch_patterns) > 0
    error_message = "waf_main_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "waf_main_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the WAF foundation on the main branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-waf-main"
}

variable "waf_main_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the WAF foundation main deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-waf-main"
}

variable "cloudfront_main_state_key_prefix" {
  description = <<-EOT
    S3 key prefix used by the cloudfront-foundation main Terraform state in the shared backend bucket.
  EOT
  type        = string
  default     = "platform/cloudfront-foundation/main/*"
}

variable "cloudfront_main_gitlab_branch_patterns" {
  description = <<-EOT
    Allowed Git branch patterns in the IAM trust policy for the cloudfront-foundation main deployment role.
  EOT
  type        = list(string)
  default     = ["main", "master"]

  validation {
    condition     = length(var.cloudfront_main_gitlab_branch_patterns) > 0
    error_message = "cloudfront_main_gitlab_branch_patterns must contain at least one branch pattern."
  }
}

variable "cloudfront_main_iam_role_name" {
  description = <<-EOT
    Name of the IAM role assumed by GitLab CI to deploy the cloudfront-foundation on the main branch.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cloudfront-main"
}

variable "cloudfront_main_iam_policy_name" {
  description = <<-EOT
    Name of the IAM policy attached to the cloudfront-foundation main deployment role.
  EOT
  type        = string
  default     = "inca-auto-deployer-gitlab-cloudfront-main"
}

variable "allow_ecr_create_repository" {
  description = <<-EOT
    Controls whether the runner publication role may create the ECR repository if it does not exist.

    Recommended usage:
    - false in a mature environment where Terraform provisions ECR beforehand
    - true only if you explicitly want CI to bootstrap the repository
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = <<-EOT
    Tags applied to resources created by this stack.

    Suggested practice:
    keep tags stable across environments and only vary the environment/account markers.
  EOT
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "gitlab-oidc-roles"
  }
}
