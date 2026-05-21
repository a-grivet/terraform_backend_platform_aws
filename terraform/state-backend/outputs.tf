output "terraform_state_bucket_name" {
  description = "Name of the shared S3 bucket used as the Terraform remote backend."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_state_bucket_arn" {
  description = "ARN of the shared S3 bucket used as the Terraform remote backend."
  value       = aws_s3_bucket.terraform_state.arn
}

output "recommended_backend_keys" {
  description = "Recommended key layout for the main platform stacks."
  value = {
    ecr               = "platform/ecr/shared/terraform.tfstate"
    gitlab_oidc_roles = "platform/gitlab-oidc-roles/shared/terraform.tfstate"
    upload_dev        = "platform/upload-foundation/dev/terraform.tfstate"
    upload_main       = "platform/upload-foundation/main/terraform.tfstate"
  }
}
