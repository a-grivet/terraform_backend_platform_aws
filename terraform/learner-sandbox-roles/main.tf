provider "aws" {
  region = var.aws_region
}

locals {
  # Sandbox indices — 001, 002, 003, ...
  sandbox_indices = [for i in range(var.sandbox_role_count) : format("%03d", i + 1)]

  common_tags = merge(var.tags, { environment = var.environment })
}

# Trust policy: allows the configured deployer roles to assume a sandbox role.
# Phase 1: the GitLab CI learner-sandbox role is the deployer (tests the chain from CI).
# Phase 2: the deployment ECS task role will be added once built.
# In production with real learner accounts, this becomes a cross-account trust.
data "aws_iam_policy_document" "sandbox_assume_role" {
  statement {
    sid     = "AllowDeployerRoles"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.deployer_role_arns
    }
  }
}

resource "aws_iam_role" "learner_sandbox" {
  for_each = toset(local.sandbox_indices)

  name               = "inca-learner-sandbox-${each.key}"
  description        = "Simulated learner account sandbox role ${each.key} for INCA deployment testing."
  assume_role_policy = data.aws_iam_policy_document.sandbox_assume_role.json

  tags = merge(local.common_tags, { sandbox_index = each.key })
}

resource "aws_iam_role_policy" "learner_sandbox_permissions" {
  for_each = aws_iam_role.learner_sandbox

  name = "inca-learner-sandbox-${each.key}-permissions"
  role = aws_iam_role.learner_sandbox[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowLabTerraformActions"
        Effect   = "Allow"
        Action   = var.allowed_terraform_actions
        Resource = "*"
      }
    ]
  })
}
