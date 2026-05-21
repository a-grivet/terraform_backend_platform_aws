variable "aws_region" {
  description = "AWS region hosting the sandbox IAM roles."
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name used in resource naming."
  type        = string
  default     = "dev"
}

variable "sandbox_role_count" {
  description = "Number of learner sandbox roles to create."
  type        = number
  default     = 3
}

variable "deployer_role_arns" {
  description = <<-EOT
    Full ARNs of IAM roles allowed to assume the sandbox roles via sts:AssumeRole.

    Phase 1 (sandbox simulation): the GitLab CI deployer role
    (inca-auto-deployer-gitlab-learner-sandbox) is used so CI can test the
    assume-role chain without a real deployment ECS task.

    Phase 2 (deployment runner): add the deployment ECS task role ARN here once
    the deployment-foundation stack is built.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.deployer_role_arns) > 0
    error_message = "deployer_role_arns must contain at least one ARN."
  }
}

variable "allowed_terraform_actions" {
  description = "IAM actions the sandbox roles are permitted to perform. Restrict to what Terraform labs actually need."
  type        = list(string)
  default = [
    # EC2 — VPC, subnets, security groups, instances
    "ec2:Describe*",
    "ec2:CreateVpc",
    "ec2:DeleteVpc",
    "ec2:ModifyVpcAttribute",
    "ec2:CreateSubnet",
    "ec2:DeleteSubnet",
    "ec2:ModifySubnetAttribute",
    "ec2:CreateInternetGateway",
    "ec2:DeleteInternetGateway",
    "ec2:AttachInternetGateway",
    "ec2:DetachInternetGateway",
    "ec2:CreateRouteTable",
    "ec2:DeleteRouteTable",
    "ec2:CreateRoute",
    "ec2:DeleteRoute",
    "ec2:AssociateRouteTable",
    "ec2:DisassociateRouteTable",
    "ec2:CreateSecurityGroup",
    "ec2:DeleteSecurityGroup",
    "ec2:AuthorizeSecurityGroupIngress",
    "ec2:AuthorizeSecurityGroupEgress",
    "ec2:RevokeSecurityGroupIngress",
    "ec2:RevokeSecurityGroupEgress",
    "ec2:RunInstances",
    "ec2:TerminateInstances",
    "ec2:StopInstances",
    "ec2:StartInstances",
    "ec2:CreateTags",
    "ec2:DeleteTags",
    # S3 — bucket + object lifecycle
    "s3:CreateBucket",
    "s3:DeleteBucket",
    "s3:GetBucketPolicy",
    "s3:PutBucketPolicy",
    "s3:DeleteBucketPolicy",
    "s3:GetBucketVersioning",
    "s3:PutBucketVersioning",
    "s3:GetBucketPublicAccessBlock",
    "s3:PutBucketPublicAccessBlock",
    "s3:GetEncryptionConfiguration",
    "s3:PutEncryptionConfiguration",
    "s3:GetBucketTagging",
    "s3:PutBucketTagging",
    "s3:ListBucket",
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    # IAM — scoped to allow lab role management
    "iam:GetRole",
    "iam:CreateRole",
    "iam:DeleteRole",
    "iam:AttachRolePolicy",
    "iam:DetachRolePolicy",
    "iam:PutRolePolicy",
    "iam:DeleteRolePolicy",
    "iam:GetRolePolicy",
    "iam:ListRolePolicies",
    "iam:ListAttachedRolePolicies",
    "iam:PassRole",
    "iam:TagRole",
    "iam:UntagRole",
    # STS — for reading caller identity inside Terraform
    "sts:GetCallerIdentity"
  ]
}

variable "tags" {
  description = "Tags applied to sandbox IAM resources."
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "inca-auto-deployer"
    component  = "learner-sandbox-roles"
  }
}
