variable "aws_region" {
  description = "AWS region for WAF resources (must match the region of protected resources)."
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
}

variable "allowed_country_codes" {
  description = "List of ISO 3166-1 alpha-2 country codes allowed through the WAF. All other origins are blocked."
  type        = list(string)
  default     = ["FR"]
}

variable "rate_limit_per_ip" {
  description = "Maximum number of requests per IP per 5-minute window before blocking."
  type        = number
  default     = 100
}

variable "ip_allowlist" {
  description = "CIDR ranges that bypass all WAF rules (e.g. CI runner IPs). Leave empty to disable."
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "Retention period in days for WAF CloudWatch logs."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags applied to WAF resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "waf-foundation"
  }
}
