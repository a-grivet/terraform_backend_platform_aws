provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # This stack centralizes GitLab OIDC access to AWS for this repository.
  # It currently provisions:
  # - the runner/ECR push role
  # - the upload foundation deployment roles for the dev and main branches

  # This stack is designed to be portable across AWS accounts.
  # The repository ARN is derived from the current account and region so that
  # the same code can be applied in:
  # - a personal/professional test account today
  # - the future management account later
  repository_arn = "arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.repository_name}"
  terraform_state_backend_bucket_name = coalesce(
    var.terraform_state_backend_bucket_name,
    "inca-terraform-state-${data.aws_caller_identity.current.account_id}"
  )
  terraform_state_backend_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.terraform_state_backend_bucket_name}"
  upload_dev_state_objects_arn        = "${local.terraform_state_backend_bucket_arn}/${var.upload_dev_state_key_prefix}"
  upload_main_state_objects_arn       = "${local.terraform_state_backend_bucket_arn}/${var.upload_main_state_key_prefix}"
  gitlab_oidc_roles_state_objects_arn = "${local.terraform_state_backend_bucket_arn}/${var.gitlab_oidc_roles_state_key_prefix}"
  ecr_state_objects_arn               = "${local.terraform_state_backend_bucket_arn}/${var.ecr_state_key_prefix}"
  validation_dev_state_objects_arn    = "${local.terraform_state_backend_bucket_arn}/${var.validation_dev_state_key_prefix}"
  validation_main_state_objects_arn   = "${local.terraform_state_backend_bucket_arn}/${var.validation_main_state_key_prefix}"
  learner_sandbox_state_objects_arn   = "${local.terraform_state_backend_bucket_arn}/${var.learner_sandbox_state_key_prefix}"
  cognito_dev_state_objects_arn       = "${local.terraform_state_backend_bucket_arn}/${var.cognito_dev_state_key_prefix}"
  cognito_main_state_objects_arn      = "${local.terraform_state_backend_bucket_arn}/${var.cognito_main_state_key_prefix}"
  deployment_dev_state_objects_arn    = "${local.terraform_state_backend_bucket_arn}/${var.deployment_dev_state_key_prefix}"
  deployment_main_state_objects_arn   = "${local.terraform_state_backend_bucket_arn}/${var.deployment_main_state_key_prefix}"
  waf_dev_state_objects_arn           = "${local.terraform_state_backend_bucket_arn}/${var.waf_dev_state_key_prefix}"
  waf_main_state_objects_arn          = "${local.terraform_state_backend_bucket_arn}/${var.waf_main_state_key_prefix}"
  cloudfront_dev_state_objects_arn    = "${local.terraform_state_backend_bucket_arn}/${var.cloudfront_dev_state_key_prefix}"
  cloudfront_main_state_objects_arn   = "${local.terraform_state_backend_bucket_arn}/${var.cloudfront_main_state_key_prefix}"
  upload_dev_bucket_objects_arn       = "arn:${data.aws_partition.current.partition}:s3:::inca-terraform-dev-${data.aws_caller_identity.current.account_id}/*"
  upload_main_bucket_objects_arn      = "arn:${data.aws_partition.current.partition}:s3:::inca-terraform-main-${data.aws_caller_identity.current.account_id}/*"

  # GitLab's OIDC `sub` claim includes the project path and the Git ref.
  # Restricting this claim is what prevents any GitLab project from assuming the role.
  #
  # Example resulting pattern:
  # project_path:inca/inca-auto-deployer:ref_type:branch:ref:main
  allowed_sub_patterns = [
    for branch_pattern in var.gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  upload_dev_allowed_sub_patterns = [
    for branch_pattern in var.upload_dev_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  upload_main_allowed_sub_patterns = [
    for branch_pattern in var.upload_main_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  gitlab_oidc_admin_allowed_sub_patterns = [
    for branch_pattern in var.gitlab_oidc_admin_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  validation_dev_allowed_sub_patterns = [
    for branch_pattern in var.validation_dev_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  learner_sandbox_allowed_sub_patterns = [
    for branch_pattern in var.learner_sandbox_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  cognito_dev_allowed_sub_patterns = [
    for branch_pattern in var.cognito_dev_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  cognito_main_allowed_sub_patterns = [
    for branch_pattern in var.cognito_main_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  deployment_dev_allowed_sub_patterns = [
    for branch_pattern in var.deployment_dev_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  deployment_main_allowed_sub_patterns = [
    for branch_pattern in var.deployment_main_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  waf_dev_allowed_sub_patterns = [
    for branch_pattern in var.waf_dev_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  waf_main_allowed_sub_patterns = [
    for branch_pattern in var.waf_main_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  cloudfront_dev_allowed_sub_patterns = [
    for branch_pattern in var.cloudfront_dev_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  cloudfront_main_allowed_sub_patterns = [
    for branch_pattern in var.cloudfront_main_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]
  validation_main_allowed_sub_patterns = [
    for branch_pattern in var.validation_main_gitlab_branch_patterns :
    "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${branch_pattern}"
  ]

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.gitlab[0].arn : var.existing_oidc_provider_arn
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  count = var.create_oidc_provider ? 1 : 0

  url = "https://${var.gitlab_domain}"

  client_id_list = [
    var.gitlab_audience
  ]

  thumbprint_list = [
    var.gitlab_thumbprint
  ]

  tags = var.tags
}

# Trust policy for the runner role used to push the Terraform runner image to ECR.
data "aws_iam_policy_document" "assume_role_gitlab" {
  statement {
    sid     = "AllowGitLabOidcAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # Restrict the token to the expected audience configured in GitLab CI.
    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    # Restrict the role assumption to the expected repository and branches.
    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.allowed_sub_patterns
    }
  }
}

# Trust policy for the upload foundation deployment role used from the dev branch.
data "aws_iam_policy_document" "assume_role_gitlab_upload_dev" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleUploadDev"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.upload_dev_allowed_sub_patterns
    }
  }
}

# Trust policy for the upload foundation deployment role used from the main branch.
data "aws_iam_policy_document" "assume_role_gitlab_upload_main" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleUploadMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.upload_main_allowed_sub_patterns
    }
  }
}

data "aws_iam_policy_document" "assume_role_gitlab_oidc_admin" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleGitLabOidcAdmin"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.gitlab_oidc_admin_allowed_sub_patterns
    }
  }
}

data "aws_iam_policy_document" "assume_role_gitlab_validation_dev" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleValidationDev"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.validation_dev_allowed_sub_patterns
    }
  }
}

data "aws_iam_policy_document" "assume_role_gitlab_validation_main" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleValidationMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.validation_main_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_ecr_push" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab.json
  tags               = var.tags
}

resource "aws_iam_role" "gitlab_upload_dev" {
  name               = var.upload_dev_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_upload_dev.json
  tags               = var.tags
}

resource "aws_iam_role" "gitlab_upload_main" {
  name               = var.upload_main_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_upload_main.json
  tags               = var.tags
}

resource "aws_iam_role" "gitlab_oidc_admin" {
  name               = var.gitlab_oidc_admin_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_oidc_admin.json
  tags               = var.tags
}

resource "aws_iam_role" "gitlab_validation_dev" {
  name               = var.validation_dev_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_validation_dev.json
  tags               = var.tags
}

resource "aws_iam_role" "gitlab_validation_main" {
  name               = var.validation_main_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_validation_main.json
  tags               = var.tags
}

data "aws_iam_policy_document" "assume_role_gitlab_learner_sandbox" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleLearnerSandbox"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.learner_sandbox_allowed_sub_patterns
    }
  }
}

data "aws_iam_policy_document" "assume_role_gitlab_cognito_dev" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleCognitoDev"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.cognito_dev_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_learner_sandbox" {
  name               = var.learner_sandbox_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_learner_sandbox.json
  tags               = var.tags
}

resource "aws_iam_role" "gitlab_cognito_dev" {
  name               = var.cognito_dev_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_cognito_dev.json
  tags               = var.tags
}

# Permissions required by the runner image publication flow.
data "aws_iam_policy_document" "gitlab_ecr_push" {
  statement {
    sid    = "AllowEcrAuthorizationToken"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowPushToRunnerRepository"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [local.repository_arn]
  }

  dynamic "statement" {
    for_each = var.allow_ecr_create_repository ? [1] : []

    content {
      sid    = "AllowRepositoryBootstrap"
      effect = "Allow"

      actions = [
        "ecr:CreateRepository"
      ]

      resources = ["*"]
    }
  }
}

# Permissions required to provision and update the upload foundation stack on dev.
# The scope is intentionally broad for now because the stack creates foundational
# AWS resources across multiple services. This can be tightened later when the
# infrastructure stabilizes.
data "aws_iam_policy_document" "gitlab_upload_dev" {
  statement {
    sid    = "AllowTerraformBackendBucketListingForUploadDev"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [local.terraform_state_backend_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.upload_dev_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForUploadDev"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject"
    ]

    resources = [local.upload_dev_state_objects_arn]
  }

  statement {
    sid    = "AllowS3UploadFoundationManagement"
    effect = "Allow"

    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketAcl",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketLocation",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketPolicy",
      "s3:GetBucketWebsite",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketLogging",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketNotification",
      "s3:PutBucketPolicy",
      "s3:PutBucketNotification",
      "s3:DeleteBucketPolicy",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:DeleteBucketTagging",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:DeleteBucketPublicAccessBlock",
      "s3:GetBucketCORS",
      "s3:PutBucketCORS",
      "s3:DeleteBucketCORS"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowS3UploadFoundationObjectManagement"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion"
    ]

    resources = [local.upload_dev_bucket_objects_arn]
  }

  statement {
    sid    = "AllowDynamoDbUploadFoundationManagement"
    effect = "Allow"

    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:GetItem",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTable",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:ListTagsOfResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowIamRoleAndPolicyManagementForUploadFoundation"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowLambdaUploadFoundationManagement"
    effect = "Allow"

    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:ListVersionsByFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:TagResource",
      "lambda:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayV2UploadFoundationManagement"
    effect = "Allow"

    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
      "apigateway:TagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagement"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowSnsUploadAlertsManagement"
    effect = "Allow"

    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchAlarmsForUploadFoundation"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayLogDeliveryForUploadFoundation"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

}

# Permissions required to provision and update the upload foundation stack on main.
# The scope is intentionally aligned with the dev role so that the same Terraform
# stack can be planned and applied safely in both environments.
data "aws_iam_policy_document" "gitlab_upload_main" {
  statement {
    sid    = "AllowTerraformBackendBucketListingForUploadMain"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [local.terraform_state_backend_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.upload_main_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForUploadMain"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [local.upload_main_state_objects_arn]
  }

  statement {
    sid    = "AllowS3UploadFoundationManagement"
    effect = "Allow"

    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketAcl",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketLocation",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketPolicy",
      "s3:GetBucketWebsite",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketLogging",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketNotification",
      "s3:PutBucketPolicy",
      "s3:PutBucketNotification",
      "s3:DeleteBucketPolicy",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:DeleteBucketTagging",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:DeleteBucketPublicAccessBlock",
      "s3:GetBucketCORS",
      "s3:PutBucketCORS",
      "s3:DeleteBucketCORS"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowS3UploadFoundationObjectManagement"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging"
    ]

    resources = [local.upload_main_bucket_objects_arn]
  }

  statement {
    sid    = "AllowDynamoDbUploadFoundationManagement"
    effect = "Allow"

    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:GetItem",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTable",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:ListTagsOfResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowIamRoleAndPolicyManagementForUploadFoundation"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowLambdaUploadFoundationManagement"
    effect = "Allow"

    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:ListVersionsByFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:TagResource",
      "lambda:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayV2UploadFoundationManagement"
    effect = "Allow"

    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
      "apigateway:TagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagement"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowSnsUploadAlertsManagement"
    effect = "Allow"

    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchAlarmsForUploadFoundation"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayLogDeliveryForUploadFoundation"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }


}

data "aws_iam_policy_document" "gitlab_oidc_admin" {
  statement {
    sid    = "AllowTerraformBackendBucketListingForGitLabFoundation"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [local.terraform_state_backend_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        var.gitlab_oidc_roles_state_key_prefix,
        var.ecr_state_key_prefix
      ]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForGitLabFoundation"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject"
    ]

    resources = [
      local.gitlab_oidc_roles_state_objects_arn,
      local.ecr_state_objects_arn
    ]
  }

  statement {
    sid    = "AllowOidcProviderManagementForGitLabFoundation"
    effect = "Allow"

    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowIamRoleAndPolicyManagementForGitLabFoundation"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEcrRepositoryBootstrapForGitLabFoundation"
    effect = "Allow"

    actions = [
      "ecr:CreateRepository"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEcrRepositoryManagementForGitLabFoundation"
    effect = "Allow"

    actions = [
      "ecr:DeleteLifecyclePolicy",
      "ecr:DeleteRepository",
      "ecr:DeleteRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:ListTagsForResource",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:TagResource",
      "ecr:UntagResource"
    ]

    resources = [local.repository_arn]
  }
}

data "aws_iam_policy_document" "gitlab_validation_dev" {
  statement {
    sid    = "AllowTerraformBackendBucketListingForValidationDev"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [local.terraform_state_backend_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.validation_dev_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForValidationDev"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [local.validation_dev_state_objects_arn]
  }

  statement {
    sid    = "AllowIamRoleAndPolicyManagementForValidationFoundation"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForValidationFoundation"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEventBridgeValidationFoundationManagement"
    effect = "Allow"

    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:EnableRule",
      "events:DisableRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:ListTargetsByRule",
      "events:ListTagsForResource",
      "events:TagResource",
      "events:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEc2ValidationFoundationNetworkManagement"
    effect = "Allow"

    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribePrefixLists",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcs",
      "ec2:DescribeFlowLogs",
      "ec2:DescribeTags",
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:CreateFlowLogs",
      "ec2:DeleteFlowLogs",
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEcsValidationFoundationManagement"
    effect = "Allow"

    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:DescribeClusters",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:ListTagsForResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEcrDescribeImagesForValidationFoundation"
    effect = "Allow"

    actions = [
      "ecr:DescribeImages"
    ]

    resources = [local.repository_arn]
  }

  statement {
    sid    = "AllowSnsValidationAlertsManagement"
    effect = "Allow"

    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchAlarmsForValidationFoundation"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowLogsMetricFiltersForValidationFoundation"
    effect = "Allow"

    actions = [
      "logs:PutMetricFilter",
      "logs:DeleteMetricFilter",
      "logs:DescribeMetricFilters",
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "gitlab_validation_main" {
  statement {
    sid    = "AllowTerraformBackendBucketListingForValidationMain"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [local.terraform_state_backend_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.validation_main_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForValidationMain"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [local.validation_main_state_objects_arn]
  }

  statement {
    sid    = "AllowIamRoleAndPolicyManagementForValidationFoundation"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForValidationFoundation"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEventBridgeValidationFoundationManagement"
    effect = "Allow"

    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:EnableRule",
      "events:DisableRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:ListTargetsByRule",
      "events:ListTagsForResource",
      "events:TagResource",
      "events:UntagResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEc2ValidationFoundationNetworkManagement"
    effect = "Allow"

    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribePrefixLists",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcAttribute",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcs",
      "ec2:DescribeFlowLogs",
      "ec2:DescribeTags",
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:CreateFlowLogs",
      "ec2:DeleteFlowLogs",
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEcsValidationFoundationManagement"
    effect = "Allow"

    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:DescribeClusters",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:ListTagsForResource"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEcrDescribeImagesForValidationFoundation"
    effect = "Allow"

    actions = [
      "ecr:DescribeImages"
    ]

    resources = [local.repository_arn]
  }

  statement {
    sid    = "AllowSnsValidationAlertsManagement"
    effect = "Allow"

    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchAlarmsForValidationFoundation"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowLogsMetricFiltersForValidationFoundation"
    effect = "Allow"

    actions = [
      "logs:PutMetricFilter",
      "logs:DeleteMetricFilter",
      "logs:DescribeMetricFilters",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "gitlab_ecr_push" {
  name   = var.iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_ecr_push.json
  tags   = var.tags
}

resource "aws_iam_policy" "gitlab_upload_dev" {
  name   = var.upload_dev_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_upload_dev.json
  tags   = var.tags
}

resource "aws_iam_policy" "gitlab_upload_main" {
  name   = var.upload_main_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_upload_main.json
  tags   = var.tags
}

resource "aws_iam_policy" "gitlab_oidc_admin" {
  name   = var.gitlab_oidc_admin_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_oidc_admin.json
  tags   = var.tags
}

resource "aws_iam_policy" "gitlab_validation_dev" {
  name   = var.validation_dev_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_validation_dev.json
  tags   = var.tags
}

resource "aws_iam_policy" "gitlab_validation_main" {
  name   = var.validation_main_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_validation_main.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_ecr_push" {
  role       = aws_iam_role.gitlab_ecr_push.name
  policy_arn = aws_iam_policy.gitlab_ecr_push.arn
}

resource "aws_iam_role_policy_attachment" "gitlab_upload_dev" {
  role       = aws_iam_role.gitlab_upload_dev.name
  policy_arn = aws_iam_policy.gitlab_upload_dev.arn
}

resource "aws_iam_role_policy_attachment" "gitlab_upload_main" {
  role       = aws_iam_role.gitlab_upload_main.name
  policy_arn = aws_iam_policy.gitlab_upload_main.arn
}

resource "aws_iam_role_policy_attachment" "gitlab_oidc_admin" {
  role       = aws_iam_role.gitlab_oidc_admin.name
  policy_arn = aws_iam_policy.gitlab_oidc_admin.arn
}

resource "aws_iam_role_policy_attachment" "gitlab_validation_dev" {
  role       = aws_iam_role.gitlab_validation_dev.name
  policy_arn = aws_iam_policy.gitlab_validation_dev.arn
}

resource "aws_iam_role_policy_attachment" "gitlab_validation_main" {
  role       = aws_iam_role.gitlab_validation_main.name
  policy_arn = aws_iam_policy.gitlab_validation_main.arn
}

# Permissions required to deploy the learner-sandbox-roles stack (IAM roles only).
data "aws_iam_policy_document" "gitlab_learner_sandbox" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForLearnerSandbox"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.learner_sandbox_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForLearnerSandbox"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject"
    ]
    resources = [local.learner_sandbox_state_objects_arn]
  }

  statement {
    sid    = "AllowIamSandboxRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowStsCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# Permissions required to deploy the Cognito stack.
data "aws_iam_policy_document" "gitlab_cognito_dev" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForCognitoDev"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.cognito_dev_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForCognitoDev"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject"
    ]
    resources = [local.cognito_dev_state_objects_arn]
  }

  statement {
    sid    = "AllowCognitoUserPoolManagement"
    effect = "Allow"
    actions = [
      "cognito-idp:CreateUserPool",
      "cognito-idp:DeleteUserPool",
      "cognito-idp:DescribeUserPool",
      "cognito-idp:UpdateUserPool",
      "cognito-idp:GetUserPoolMfaConfig",
      "cognito-idp:SetUserPoolMfaConfig",
      "cognito-idp:TagResource",
      "cognito-idp:UntagResource",
      "cognito-idp:ListTagsForResource",
      "cognito-idp:CreateUserPoolClient",
      "cognito-idp:DeleteUserPoolClient",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:UpdateUserPoolClient",
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminDeleteUser",
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:ListUsers"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowWafv2AssociationForCognito"
    effect = "Allow"
    actions = [
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:GetWebACL",
      "cognito-idp:AssociateWebACL",
      "cognito-idp:DisassociateWebACL",
      "cognito-idp:GetWebACLForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowReadWafDevStateForCognitoDev"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.waf_dev_state_key_prefix]
    }
  }

  statement {
    sid       = "AllowGetWafDevStateObjectForCognitoDev"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.waf_dev_state_objects_arn]
  }
}

resource "aws_iam_policy" "gitlab_learner_sandbox" {
  name   = var.learner_sandbox_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_learner_sandbox.json
  tags   = var.tags
}

resource "aws_iam_policy" "gitlab_cognito_dev" {
  name   = var.cognito_dev_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_cognito_dev.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_learner_sandbox" {
  role       = aws_iam_role.gitlab_learner_sandbox.name
  policy_arn = aws_iam_policy.gitlab_learner_sandbox.arn
}

resource "aws_iam_role_policy_attachment" "gitlab_cognito_dev" {
  role       = aws_iam_role.gitlab_cognito_dev.name
  policy_arn = aws_iam_policy.gitlab_cognito_dev.arn
}

data "aws_iam_policy_document" "assume_role_gitlab_deployment_dev" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleDeploymentDev"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.deployment_dev_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_deployment_dev" {
  name               = var.deployment_dev_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_deployment_dev.json
  tags               = var.tags
}

# Permissions required to provision the deployment-foundation stack:
# Lambda, Step Functions, ECS cluster/task definition, IAM roles, API Gateway,
# and CloudWatch log groups.
data "aws_iam_policy_document" "gitlab_deployment_dev" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForDeploymentDev"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.deployment_dev_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForDeploymentDev"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [local.deployment_dev_state_objects_arn]
  }

  statement {
    sid    = "AllowIamRoleAndPolicyManagementForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLambdaDeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:ListVersionsByFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowStepFunctionsDeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "states:CreateStateMachine",
      "states:DeleteStateMachine",
      "states:DescribeStateMachine",
      "states:UpdateStateMachine",
      "states:ValidateStateMachineDefinition",
      "states:ListStateMachineVersions",
      "states:TagResource",
      "states:UntagResource",
      "states:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEcsDeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:DescribeClusters",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayV2DeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
      "apigateway:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEcrDescribeImagesForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "ecr:DescribeImages",
    ]
    resources = [local.repository_arn]
  }

  statement {
    sid    = "AllowSnsDeploymentAlertsManagement"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchAlarmsForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLogsMetricFiltersForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "logs:PutMetricFilter",
      "logs:DeleteMetricFilter",
      "logs:DescribeMetricFilters",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayLogDeliveryForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowDeploymentSmokeTestOps"
    effect = "Allow"
    actions = [
      "states:DescribeExecution",
      "states:GetExecutionHistory",
      "dynamodb:GetItem",
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminDeleteUser",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowReadCognitoDevStateForDeploymentDev"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.cognito_dev_state_key_prefix]
    }
  }

  statement {
    sid       = "AllowGetCognitoDevStateObjectForDeploymentDev"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.cognito_dev_state_objects_arn]
  }

  statement {
    sid       = "AllowReadValidationDevStateForDeploymentDev"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.validation_dev_state_key_prefix]
    }
  }

  statement {
    sid       = "AllowGetValidationDevStateObjectForDeploymentDev"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.validation_dev_state_objects_arn]
  }
}

resource "aws_iam_policy" "gitlab_deployment_dev" {
  name   = var.deployment_dev_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_deployment_dev.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_deployment_dev" {
  role       = aws_iam_role.gitlab_deployment_dev.name
  policy_arn = aws_iam_policy.gitlab_deployment_dev.arn
}

# ---------------------------------------------------------------------------
# WAF foundation — dev deployment role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_gitlab_waf_dev" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleWafDev"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.waf_dev_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_waf_dev" {
  name               = var.waf_dev_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_waf_dev.json
  tags               = var.tags
}

# Permissions required to provision the waf-foundation stack:
# WAF Web ACL, IP set, logging configuration, and CloudWatch log group.
data "aws_iam_policy_document" "gitlab_waf_dev" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForWafDev"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.waf_dev_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForWafDev"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [local.waf_dev_state_objects_arn]
  }

  statement {
    sid    = "AllowWafv2ManagementForWafFoundation"
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:GetWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:ListWebACLs",
      "wafv2:CreateIPSet",
      "wafv2:DeleteIPSet",
      "wafv2:GetIPSet",
      "wafv2:UpdateIPSet",
      "wafv2:ListIPSets",
      "wafv2:PutLoggingConfiguration",
      "wafv2:GetLoggingConfiguration",
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:ListLoggingConfigurations",
      "wafv2:ListTagsForResource",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:CheckCapacity",
      "wafv2:DescribeManagedRuleGroup",
      "wafv2:ListAvailableManagedRuleGroups",
      "wafv2:ListAvailableManagedRuleGroupVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForWafFoundation"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:PutResourcePolicy",
      "logs:DeleteResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLogDeliveryForWafLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gitlab_waf_dev" {
  name   = var.waf_dev_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_waf_dev.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_waf_dev" {
  role       = aws_iam_role.gitlab_waf_dev.name
  policy_arn = aws_iam_policy.gitlab_waf_dev.arn
}

# ---------------------------------------------------------------------------
# CloudFront foundation — dev deployment role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_gitlab_cloudfront_dev" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleCloudfrontDev"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.cloudfront_dev_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_cloudfront_dev" {
  name               = var.cloudfront_dev_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_cloudfront_dev.json
  tags               = var.tags
}

# Permissions required to provision cloudfront-foundation:
# WAF (CLOUDFRONT scope, us-east-1), CloudFront distributions,
# CloudWatch log groups (us-east-1), and read access to upload/deployment state.
data "aws_iam_policy_document" "gitlab_cloudfront_dev" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForCloudfrontDev"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.cloudfront_dev_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForCloudfrontDev"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [local.cloudfront_dev_state_objects_arn]
  }

  statement {
    sid    = "AllowRemoteStateReadForUploadAndDeploymentFoundations"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${local.terraform_state_backend_bucket_arn}/platform/upload-foundation/dev/terraform.tfstate",
      "${local.terraform_state_backend_bucket_arn}/platform/deployment-foundation/dev/terraform.tfstate",
    ]
  }

  statement {
    sid    = "AllowWafv2CloudfrontManagement"
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:GetWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:ListWebACLs",
      "wafv2:CreateIPSet",
      "wafv2:DeleteIPSet",
      "wafv2:GetIPSet",
      "wafv2:UpdateIPSet",
      "wafv2:ListIPSets",
      "wafv2:PutLoggingConfiguration",
      "wafv2:GetLoggingConfiguration",
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:ListLoggingConfigurations",
      "wafv2:ListTagsForResource",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:CheckCapacity",
      "wafv2:DescribeManagedRuleGroup",
      "wafv2:ListAvailableManagedRuleGroups",
      "wafv2:ListAvailableManagedRuleGroupVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudFrontDistributionManagement"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:ListDistributions",
      "cloudfront:ListTagsForResource",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForCloudfrontWaf"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:PutResourcePolicy",
      "logs:DeleteResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLogDeliveryForCloudfrontWafLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowStsGetCallerIdentityForCloudfrontDev"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gitlab_cloudfront_dev" {
  name   = var.cloudfront_dev_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_cloudfront_dev.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_cloudfront_dev" {
  role       = aws_iam_role.gitlab_cloudfront_dev.name
  policy_arn = aws_iam_policy.gitlab_cloudfront_dev.arn
}

# ---------------------------------------------------------------------------
# Deployment foundation — main deployment role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_gitlab_deployment_main" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleDeploymentMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.deployment_main_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_deployment_main" {
  name               = var.deployment_main_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_deployment_main.json
  tags               = var.tags
}

data "aws_iam_policy_document" "gitlab_deployment_main" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForDeploymentMain"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.deployment_main_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForDeploymentMain"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [local.deployment_main_state_objects_arn]
  }

  statement {
    sid    = "AllowIamRoleAndPolicyManagementForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PassRole",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLambdaDeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:ListVersionsByFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowStepFunctionsDeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "states:CreateStateMachine",
      "states:DeleteStateMachine",
      "states:DescribeStateMachine",
      "states:UpdateStateMachine",
      "states:ValidateStateMachineDefinition",
      "states:ListStateMachineVersions",
      "states:TagResource",
      "states:UntagResource",
      "states:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEcsDeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DeleteCluster",
      "ecs:DescribeClusters",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayV2DeploymentFoundationManagement"
    effect = "Allow"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
      "apigateway:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEcrDescribeImagesForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "ecr:DescribeImages",
    ]
    resources = [local.repository_arn]
  }

  statement {
    sid    = "AllowSnsDeploymentAlertsManagement"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchAlarmsForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLogsMetricFiltersForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "logs:PutMetricFilter",
      "logs:DeleteMetricFilter",
      "logs:DescribeMetricFilters",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowApiGatewayLogDeliveryForDeploymentFoundation"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowDeploymentSmokeTestOps"
    effect = "Allow"
    actions = [
      "states:DescribeExecution",
      "states:GetExecutionHistory",
      "dynamodb:GetItem",
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminDeleteUser",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowReadCognitoMainStateForDeploymentMain"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.cognito_main_state_key_prefix]
    }
  }

  statement {
    sid       = "AllowGetCognitoMainStateObjectForDeploymentMain"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.cognito_main_state_objects_arn]
  }

  statement {
    sid       = "AllowReadValidationMainStateForDeploymentMain"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.validation_main_state_key_prefix]
    }
  }

  statement {
    sid       = "AllowGetValidationMainStateObjectForDeploymentMain"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.validation_main_state_objects_arn]
  }
}

resource "aws_iam_policy" "gitlab_deployment_main" {
  name   = var.deployment_main_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_deployment_main.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_deployment_main" {
  role       = aws_iam_role.gitlab_deployment_main.name
  policy_arn = aws_iam_policy.gitlab_deployment_main.arn
}

# ---------------------------------------------------------------------------
# Cognito — main deployment role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_gitlab_cognito_main" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleCognitoMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.cognito_main_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_cognito_main" {
  name               = var.cognito_main_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_cognito_main.json
  tags               = var.tags
}

data "aws_iam_policy_document" "gitlab_cognito_main" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForCognitoMain"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.cognito_main_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForCognitoMain"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject"
    ]
    resources = [local.cognito_main_state_objects_arn]
  }

  statement {
    sid    = "AllowCognitoUserPoolManagement"
    effect = "Allow"
    actions = [
      "cognito-idp:CreateUserPool",
      "cognito-idp:DeleteUserPool",
      "cognito-idp:DescribeUserPool",
      "cognito-idp:UpdateUserPool",
      "cognito-idp:GetUserPoolMfaConfig",
      "cognito-idp:SetUserPoolMfaConfig",
      "cognito-idp:TagResource",
      "cognito-idp:UntagResource",
      "cognito-idp:ListTagsForResource",
      "cognito-idp:CreateUserPoolClient",
      "cognito-idp:DeleteUserPoolClient",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:UpdateUserPoolClient",
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminDeleteUser",
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:ListUsers"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowWafv2AssociationForCognito"
    effect = "Allow"
    actions = [
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:GetWebACL",
      "cognito-idp:AssociateWebACL",
      "cognito-idp:DisassociateWebACL",
      "cognito-idp:GetWebACLForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowReadWafMainStateForCognitoMain"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.waf_main_state_key_prefix]
    }
  }

  statement {
    sid       = "AllowGetWafMainStateObjectForCognitoMain"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.waf_main_state_objects_arn]
  }
}

resource "aws_iam_policy" "gitlab_cognito_main" {
  name   = var.cognito_main_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_cognito_main.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_cognito_main" {
  role       = aws_iam_role.gitlab_cognito_main.name
  policy_arn = aws_iam_policy.gitlab_cognito_main.arn
}

# ---------------------------------------------------------------------------
# WAF foundation — main deployment role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_gitlab_waf_main" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleWafMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.waf_main_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_waf_main" {
  name               = var.waf_main_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_waf_main.json
  tags               = var.tags
}

data "aws_iam_policy_document" "gitlab_waf_main" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForWafMain"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.waf_main_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForWafMain"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [local.waf_main_state_objects_arn]
  }

  statement {
    sid    = "AllowWafv2ManagementForWafFoundation"
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:GetWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:ListWebACLs",
      "wafv2:CreateIPSet",
      "wafv2:DeleteIPSet",
      "wafv2:GetIPSet",
      "wafv2:UpdateIPSet",
      "wafv2:ListIPSets",
      "wafv2:PutLoggingConfiguration",
      "wafv2:GetLoggingConfiguration",
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:ListLoggingConfigurations",
      "wafv2:ListTagsForResource",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:CheckCapacity",
      "wafv2:DescribeManagedRuleGroup",
      "wafv2:ListAvailableManagedRuleGroups",
      "wafv2:ListAvailableManagedRuleGroupVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForWafFoundation"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:PutResourcePolicy",
      "logs:DeleteResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLogDeliveryForWafLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gitlab_waf_main" {
  name   = var.waf_main_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_waf_main.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_waf_main" {
  role       = aws_iam_role.gitlab_waf_main.name
  policy_arn = aws_iam_policy.gitlab_waf_main.arn
}

# ---------------------------------------------------------------------------
# CloudFront foundation — main deployment role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role_gitlab_cloudfront_main" {
  statement {
    sid     = "AllowGitLabOidcAssumeRoleCloudfrontMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.gitlab_domain}:aud"
      values   = [var.gitlab_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${var.gitlab_domain}:sub"
      values   = local.cloudfront_main_allowed_sub_patterns
    }
  }
}

resource "aws_iam_role" "gitlab_cloudfront_main" {
  name               = var.cloudfront_main_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_gitlab_cloudfront_main.json
  tags               = var.tags
}

data "aws_iam_policy_document" "gitlab_cloudfront_main" {
  statement {
    sid       = "AllowTerraformBackendBucketListingForCloudfrontMain"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.terraform_state_backend_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.cloudfront_main_state_key_prefix]
    }
  }

  statement {
    sid    = "AllowTerraformBackendStateAccessForCloudfrontMain"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:DeleteObject",
    ]
    resources = [local.cloudfront_main_state_objects_arn]
  }

  statement {
    sid    = "AllowRemoteStateReadForUploadAndDeploymentFoundations"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${local.terraform_state_backend_bucket_arn}/platform/upload-foundation/main/terraform.tfstate",
      "${local.terraform_state_backend_bucket_arn}/platform/deployment-foundation/main/terraform.tfstate",
    ]
  }

  statement {
    sid    = "AllowWafv2CloudfrontManagement"
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:GetWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:ListWebACLs",
      "wafv2:CreateIPSet",
      "wafv2:DeleteIPSet",
      "wafv2:GetIPSet",
      "wafv2:UpdateIPSet",
      "wafv2:ListIPSets",
      "wafv2:PutLoggingConfiguration",
      "wafv2:GetLoggingConfiguration",
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:ListLoggingConfigurations",
      "wafv2:ListTagsForResource",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:CheckCapacity",
      "wafv2:DescribeManagedRuleGroup",
      "wafv2:ListAvailableManagedRuleGroups",
      "wafv2:ListAvailableManagedRuleGroupVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudFrontDistributionManagement"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:ListDistributions",
      "cloudfront:ListTagsForResource",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogGroupManagementForCloudfrontWaf"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:PutResourcePolicy",
      "logs:DeleteResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowLogDeliveryForCloudfrontWafLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowStsGetCallerIdentityForCloudfrontMain"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gitlab_cloudfront_main" {
  name   = var.cloudfront_main_iam_policy_name
  policy = data.aws_iam_policy_document.gitlab_cloudfront_main.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "gitlab_cloudfront_main" {
  role       = aws_iam_role.gitlab_cloudfront_main.name
  policy_arn = aws_iam_policy.gitlab_cloudfront_main.arn
}
