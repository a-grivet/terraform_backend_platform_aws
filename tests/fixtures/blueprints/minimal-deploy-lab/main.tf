# Blueprint: minimal-deploy-lab
#
# Role: Minimal AWS Terraform blueprint using only data sources — no managed
#       resources, no cost, fully idempotent across repeated applies.
#
# Purpose: Tests the full end-to-end deployment flow. Verifies that the
#          deployment Step Functions state machine correctly triggers an ECS
#          Fargate task, that the task downloads the blueprint ZIP from S3,
#          successfully assumes the learner sandbox IAM role (proving the trust
#          policy is correct), initialises the AWS provider, and completes
#          terraform apply without error. The aws_caller_identity data source
#          acts as the proof-of-execution: it can only succeed if AWS
#          credentials are valid, i.e. the role assumption worked.
#
# CI usage: post_deploy / smoke_test_deployment_foundation_dev

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

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  deploy_smoke_tags = {
    project    = "inca-deploy-smoke"
    managed_by = "terraform"
    scenario   = "minimal-deploy-lab"
  }
}

output "deploy_smoke_ready" {
  value = {
    account_id = data.aws_caller_identity.current.account_id
    region     = data.aws_region.current.name
    tags       = local.deploy_smoke_tags
  }
}
