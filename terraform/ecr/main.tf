provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  # The AWS provider version pinned in this stack cannot express the ECR
  # *_WITH_EXCLUSION modes on the repository resource yet. We therefore create
  # the repository with a base mutability mode, then apply the final
  # IMMUTABLE_WITH_EXCLUSION or MUTABLE_WITH_EXCLUSION setting via the AWS CLI
  # after the repository exists.
  repository_image_tag_mutability = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability) ? var.image_tag_mutability : "MUTABLE"

  image_tag_mutability_exclusion_filters = [
    for exclusion_filter in var.image_tag_mutability_exclusion_filters : {
      filterType = exclusion_filter.filter_type
      filter     = exclusion_filter.filter
    }
  ]

  image_tag_mutability_command = length(var.image_tag_mutability_exclusion_filters) > 0 ? trimspace(<<-EOT
    aws ecr put-image-tag-mutability \
      --region '${var.aws_region}' \
      --repository-name '${aws_ecr_repository.runner.name}' \
      --image-tag-mutability '${var.image_tag_mutability}' \
      --image-tag-mutability-exclusion-filters '${jsonencode(local.image_tag_mutability_exclusion_filters)}'
  EOT
    ) : trimspace(<<-EOT
    aws ecr put-image-tag-mutability \
      --region '${var.aws_region}' \
      --repository-name '${aws_ecr_repository.runner.name}' \
      --image-tag-mutability '${var.image_tag_mutability}'
  EOT
  )

  ecr_actions_pull = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:DescribeImages",
    "ecr:DescribeRepositories",
    "ecr:GetDownloadUrlForLayer"
  ]

  ecr_actions_push = concat(local.ecr_actions_pull, [
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:PutImage"
  ])

  use_repository_policy = length(var.allowed_pull_role_arns) > 0 || length(var.allowed_push_role_arns) > 0
}

resource "aws_ecr_repository" "runner" {
  name                 = var.repository_name
  image_tag_mutability = local.repository_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encrypt_with_kms ? "KMS" : "AES256"
    kms_key         = var.encrypt_with_kms ? var.kms_key_arn : null
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [image_tag_mutability]
  }
}

resource "terraform_data" "runner_image_tag_mutability" {
  triggers_replace = [
    sha1(jsonencode({
      repository_name   = aws_ecr_repository.runner.name
      aws_region        = var.aws_region
      mutability        = var.image_tag_mutability
      exclusion_filters = var.image_tag_mutability_exclusion_filters
    }))
  ]

  provisioner "local-exec" {
    command     = local.image_tag_mutability_command
    interpreter = ["/bin/sh", "-c"]
  }

  lifecycle {
    precondition {
      condition = (
        contains(["MUTABLE_WITH_EXCLUSION", "IMMUTABLE_WITH_EXCLUSION"], var.image_tag_mutability)
        || length(var.image_tag_mutability_exclusion_filters) == 0
      )
      error_message = "image_tag_mutability_exclusion_filters can only be set with MUTABLE_WITH_EXCLUSION or IMMUTABLE_WITH_EXCLUSION."
    }

    precondition {
      condition = (
        !contains(["MUTABLE_WITH_EXCLUSION", "IMMUTABLE_WITH_EXCLUSION"], var.image_tag_mutability)
        || length(var.image_tag_mutability_exclusion_filters) > 0
      )
      error_message = "At least one image tag mutability exclusion filter is required when using a WITH_EXCLUSION mode."
    }
  }

  depends_on = [aws_ecr_repository.runner]
}

resource "aws_ecr_lifecycle_policy" "runner" {
  repository = aws_ecr_repository.runner.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after test iterations"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "runner_repository" {
  count = local.use_repository_policy ? 1 : 0

  dynamic "statement" {
    for_each = length(var.allowed_pull_role_arns) > 0 ? [1] : []
    content {
      sid    = "AllowPull"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.allowed_pull_role_arns
      }

      actions = local.ecr_actions_pull
    }
  }

  dynamic "statement" {
    for_each = length(var.allowed_push_role_arns) > 0 ? [1] : []
    content {
      sid    = "AllowPush"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.allowed_push_role_arns
      }

      actions = local.ecr_actions_push
    }
  }
}

resource "aws_ecr_repository_policy" "runner" {
  count      = local.use_repository_policy ? 1 : 0
  repository = aws_ecr_repository.runner.name
  policy     = data.aws_iam_policy_document.runner_repository[0].json
}
