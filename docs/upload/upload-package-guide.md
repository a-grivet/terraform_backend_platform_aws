# Terraform Package Guide

## Purpose

This guide explains how to prepare a Terraform ZIP package that can be uploaded to the platform and validated before deployment.

It is intended for trainers and platform users who want to distribute Terraform labs to learner accounts.

## Validation Flow Overview

The current flow is:

1. prepare an upload from the platform
2. upload a ZIP package to the generated S3 location
3. mark the upload as complete
4. let the platform run the automatic validation
5. deploy the package only after a successful validation

Current lifecycle states:

- `PENDING`
- `UPLOADED`
- `VALIDATING`
- `VALIDATED`
- `VALIDATION_FAILED`

## What The Validator Checks

The current validator focuses on a first Terraform baseline:

- the ZIP can be extracted correctly
- a Terraform root can be identified
- `terraform fmt -check` passes
- `terraform init -backend=false` passes
- `terraform validate` passes

The current objective is to reject malformed or unsupported packages early. It is not yet a full deployment simulation.

## Recommended ZIP Structure

The ZIP should contain one Terraform package only.

Recommended structure:

```text
my-lab.zip
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md
└── modules/
```

Also accepted:

```text
my-lab.zip
└── my-lab/
    ├── main.tf
    ├── variables.tf
    └── versions.tf
```

Practical recommendations:

- keep one clear Terraform root per ZIP
- include `main.tf` in that root
- prefer a flat root or a single top-level folder
- avoid multiple unrelated Terraform roots in the same archive

## Provider Support Policy

The validation runner currently executes in private subnets without outbound Internet access.

Because of that, providers are not downloaded dynamically from the public Terraform registry during validation.

Current supported baseline:

- provider source: `registry.terraform.io/hashicorp/aws`
- provider version: `5.100.0`

Recommended `versions.tf` baseline:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
  }
}
```

Current recommendations:

- pin the provider version explicitly
- do not use `latest`
- do not rely on unapproved provider families

If your package requires another provider or another provider version, validation may fail until platform support is extended.

## Module Guidance

At this stage, keep the package as self-contained as possible.

Recommended:

- local modules included inside the ZIP
- simple and explicit Terraform layout
- minimal hidden assumptions

Avoid when possible:

- remote module downloads during validation
- package structures that depend on files not included in the ZIP
- implicit runtime dependencies that are not documented

## Packaging Recommendations

Before creating the ZIP:

- remove `.terraform/`
- do not include local credentials
- do not include secret files
- keep only Terraform source files and useful documentation

Good candidates to include:

- `*.tf`
- `README.md`
- module source files
- safe example variable files

Use caution with:

- `.terraform.lock.hcl`

It can help when it matches the supported provider baseline, but it can also force an unsupported version and make validation fail.

## Common Validation Failures

Typical reasons for rejection:

- no Terraform root found in the ZIP
- several competing Terraform roots in the same package
- Terraform formatting does not pass
- invalid Terraform syntax or invalid references
- unsupported provider source
- unsupported provider version
- runtime dependency on public Internet access

## Practical Authoring Checklist

Before uploading a package, check the following:

- the ZIP contains one clear Terraform root
- the Terraform root includes `main.tf`
- the code is formatted with `terraform fmt`
- the package uses `hashicorp/aws` `5.100.0`
- there are no secrets in the archive
- local modules are included in the ZIP if they are required

## Current Scope Boundary

The validator is intentionally conservative for now.

Today it supports a first safe baseline for Terraform package validation, not every Terraform ecosystem pattern.

That means:

- provider support is explicit and limited
- network assumptions are strict
- the guide will evolve as the platform expands supported package types

This document is the first version of the user guide and will be extended over time.
