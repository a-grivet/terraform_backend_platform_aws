output "upload_cloudfront_domain" {
  description = "CloudFront domain name for the upload API. Use this URL instead of the direct API Gateway endpoint."
  value       = aws_cloudfront_distribution.upload.domain_name
}

output "upload_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for the upload API."
  value       = aws_cloudfront_distribution.upload.id
}

output "deployment_cloudfront_domain" {
  description = "CloudFront domain name for the deployment API. Use this URL instead of the direct API Gateway endpoint."
  value       = aws_cloudfront_distribution.deployment.domain_name
}

output "deployment_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for the deployment API."
  value       = aws_cloudfront_distribution.deployment.id
}

output "cloudfront_waf_web_acl_arn" {
  description = "WAF Web ACL ARN (CLOUDFRONT scope, us-east-1)."
  value       = aws_wafv2_web_acl.cloudfront.arn
}

output "cloudfront_waf_log_group_name" {
  description = "CloudWatch log group name for CloudFront WAF traffic logs (us-east-1)."
  value       = aws_cloudwatch_log_group.waf_cloudfront.name
}
