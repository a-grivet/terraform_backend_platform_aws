output "current_account_id" {
  description = "AWS account ID where the stack has been applied."
  value       = data.aws_caller_identity.current.account_id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider used by the GitLab trust policy."
  value       = local.oidc_provider_arn
}

output "gitlab_role_arn" {
  description = "IAM role ARN that GitLab CI must assume with AssumeRoleWithWebIdentity."
  value       = aws_iam_role.gitlab_ecr_push.arn
}

output "gitlab_upload_dev_role_arn" {
  description = "IAM role ARN that GitLab CI must assume to deploy the upload foundation on dev."
  value       = aws_iam_role.gitlab_upload_dev.arn
}

output "gitlab_upload_main_role_arn" {
  description = "IAM role ARN that GitLab CI must assume to deploy the upload foundation on main."
  value       = aws_iam_role.gitlab_upload_main.arn
}

output "gitlab_oidc_admin_role_arn" {
  description = "IAM role ARN that GitLab CI must assume to deploy the centralized GitLab OIDC / IAM foundation stack."
  value       = aws_iam_role.gitlab_oidc_admin.arn
}

output "gitlab_validation_dev_role_arn" {
  description = "IAM role ARN that GitLab CI must assume to deploy the validation foundation on dev."
  value       = aws_iam_role.gitlab_validation_dev.arn
}

output "gitlab_validation_main_role_arn" {
  description = "IAM role ARN that GitLab CI must assume to deploy the validation foundation on main."
  value       = aws_iam_role.gitlab_validation_main.arn
}

output "repository_arn" {
  description = "Derived ARN of the ECR repository that the role is allowed to push to."
  value       = local.repository_arn
}

output "gitlab_ci_expected_variables" {
  description = "Reminder of the main CI values to wire into GitLab later."
  value = {
    aws_region                     = var.aws_region
    aws_role_arn_runner            = aws_iam_role.gitlab_ecr_push.arn
    aws_role_arn_upload_dev        = aws_iam_role.gitlab_upload_dev.arn
    aws_role_arn_upload_main       = aws_iam_role.gitlab_upload_main.arn
    aws_role_arn_gitlab_oidc_admin = aws_iam_role.gitlab_oidc_admin.arn
    aws_role_arn_validation_dev    = aws_iam_role.gitlab_validation_dev.arn
    aws_role_arn_validation_main   = aws_iam_role.gitlab_validation_main.arn
    gitlab_audience                = var.gitlab_audience
    repository_name                = var.repository_name
  }
}
