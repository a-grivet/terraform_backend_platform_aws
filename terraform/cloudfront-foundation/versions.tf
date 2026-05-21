terraform {
  required_version = ">= 1.9.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider: eu-west-3 — used for remote state data sources.
provider "aws" {
  region = var.aws_region
}

# WAF with CLOUDFRONT scope and CloudFront WAF log groups must be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
