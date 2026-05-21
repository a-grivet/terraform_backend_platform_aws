output "aws_account_id" {
  description = "AWS account ID where the repository was created."
  value       = data.aws_caller_identity.current.account_id
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.runner.name
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.runner.arn
}

output "repository_url" {
  description = "ECR repository URL used for docker login/tag/push."
  value       = aws_ecr_repository.runner.repository_url
}
