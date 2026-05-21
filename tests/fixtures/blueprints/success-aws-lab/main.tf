# Blueprint: success-aws-lab
#
# Role: Minimal AWS Terraform blueprint — initialises the AWS provider with no
#       managed resources and outputs a set of smoke-test tags.
#
# Purpose: Tests the upload and validation pipeline machinery without creating
#          real AWS resources. Validates that the upload API (API Gateway →
#          Lambda → S3 → DynamoDB), the validation Step Functions state machine
#          (ECS Fargate → terraform init/validate), and the intent status
#          transitions all work correctly end-to-end. The blueprint itself is
#          intentionally empty so that test duration and cost are negligible.
#
# CI usage:
#   post_deploy / smoke_test_upload_foundation_dev
#   post_deploy / smoke_test_upload_foundation_main
#   post_deploy / smoke_test_validation_foundation_dev  (expected final status: READY)
#   post_deploy / smoke_test_validation_foundation_main (expected final status: READY)

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

provider "aws" {
  region = var.aws_region
}

locals {
  validation_smoke_tags = {
    project    = "inca-validation-smoke"
    managed_by = "terraform"
    scenario   = "success-aws-lab"
  }
}

output "validation_smoke_ready" {
  value = local.validation_smoke_tags
}
