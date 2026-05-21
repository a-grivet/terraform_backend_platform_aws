output "web_acl_arn" {
  description = "WAF Web ACL ARN — pass this to upload-foundation, deployment-foundation, and cognito stacks to enable WAF protection."
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_id" {
  description = "WAF Web ACL ID."
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_name" {
  description = "WAF Web ACL name."
  value       = aws_wafv2_web_acl.main.name
}

output "waf_log_group_name" {
  description = "CloudWatch Logs group name receiving WAF traffic logs."
  value       = aws_cloudwatch_log_group.waf.name
}

output "ip_allowlist_arn" {
  description = "WAF IP set ARN for the CI/admin allowlist (null when allowlist is empty)."
  value       = length(var.ip_allowlist) > 0 ? aws_wafv2_ip_set.allowlist[0].arn : null
}
