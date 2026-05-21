provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  backend_bucket_name = coalesce(
    var.backend_bucket_name,
    "inca-terraform-state-${data.aws_caller_identity.current.account_id}"
  )
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.backend_bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encrypt_with_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.encrypt_with_kms ? var.kms_key_arn : null
    }
  }
}
