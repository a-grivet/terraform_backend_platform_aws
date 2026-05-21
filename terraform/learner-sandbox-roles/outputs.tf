output "sandbox_role_arns" {
  description = "ARN map of sandbox roles — keyed by index (e.g. '001')."
  value       = { for k, r in aws_iam_role.learner_sandbox : k => r.arn }
}

output "sandbox_role_names" {
  description = "Name map of sandbox roles — keyed by index."
  value       = { for k, r in aws_iam_role.learner_sandbox : k => r.name }
}
