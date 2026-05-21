# CI/CD Reference

## Table of Contents

1. [Purpose](#1-purpose)
2. [File Map](#2-file-map)
3. [Pipeline Architecture](#3-pipeline-architecture)
   - [Two-Level Design: Parent + Child Pipelines](#two-level-design-parent--child-pipelines)
   - [Parent Pipeline Stages](#parent-pipeline-stages)
   - [Child Pipeline Stages](#child-pipeline-stages)
4. [Terraform Stacks Covered](#4-terraform-stacks-covered)
5. [Pipeline Inputs](#5-pipeline-inputs)
   - [Available Inputs](#available-inputs)
   - [Confirmation Tokens](#confirmation-tokens)
6. [Path-Based Routing](#6-path-based-routing)
   - [Which Child Pipeline Is Triggered](#which-child-pipeline-is-triggered)
   - [Which Jobs Run Inside a Child Pipeline](#which-jobs-run-inside-a-child-pipeline)
7. [Operator Workflows](#7-operator-workflows)
   - [Branch = Environment: A Hard Rule](#branch--environment-a-hard-rule)
   - [Push / Auto Workflow](#push--auto-workflow)
   - [Plan Workflow](#plan-workflow)
   - [Apply Workflow](#apply-workflow)
   - [Destroy Workflow](#destroy-workflow)
8. [Plan / Apply Guardrails](#8-plan--apply-guardrails)
   - [Application Infrastructure — Cross-Pipeline Guardrail](#application-infrastructure--cross-pipeline-guardrail)
   - [Bootstrap Foundation — Same-Pipeline Guardrail](#bootstrap-foundation--same-pipeline-guardrail)
   - [Plan Artifact Contents per Stack](#plan-artifact-contents-per-stack)
   - [Terraform Plan Summary in Merge Requests](#terraform-plan-summary-in-merge-requests)
9. [Job Reference: Runner Image Pipeline](#9-job-reference-runner-image-pipeline)
10. [Job Reference: Application Infrastructure Pipeline](#10-job-reference-application-infrastructure-pipeline)
    - [Validate Stage](#validate-stage)
    - [Plan Stage](#plan-stage)
    - [Apply Stage](#apply-stage)
    - [Verify Stage (Smoke Tests)](#verify-stage-smoke-tests)
    - [Destroy Stage](#destroy-stage)
11. [Job Reference: Bootstrap Pipeline](#11-job-reference-bootstrap-pipeline)
12. [Authentication Model](#12-authentication-model)
    - [GitLab OIDC Flow](#gitlab-oidc-flow)
    - [OIDC Templates](#oidc-templates)
    - [IAM Role Split](#iam-role-split)
13. [Runner Image](#13-runner-image)
    - [Image Content](#image-content)
    - [Idempotency Check Before Build](#idempotency-check-before-build)
    - [ECR Tag Strategy](#ecr-tag-strategy)
    - [Local Build and Verification](#local-build-and-verification)
14. [Environment Injection and Variable Files](#14-environment-injection-and-variable-files)
15. [CI/CD Variables](#15-cicd-variables)
16. [GitLab Environments](#16-gitlab-environments)
17. [Quality Configuration](#17-quality-configuration)
18. [Known Limitations](#18-known-limitations)

---

## 1. Purpose

This document is the single reference for the GitLab CI/CD setup in this repository. It is derived directly from the source files and supersedes any prior documentation.

It covers: pipeline architecture, operator workflows, every job and its trigger conditions, plan/apply guardrails, authentication model, and the runner image lifecycle.

---

## 2. File Map

| File | Role |
|---|---|
| `.gitlab-ci.yml` | Parent pipeline — declares inputs, triggers child pipelines |
| `ci/_templates.yml` | Reusable YAML templates: Terraform base image, OIDC credential exchange |
| `ci/runner.yml` | Child pipeline — builds and publishes the Terraform runner image |
| `ci/inca-pipeline.yml` | Child pipeline — INCA delivery workflow: upload, validation, deployment, learner-sandbox; also defines shared stages, variables, and cross-cutting quality jobs |
| `ci/api-security.yml` | Child pipeline — API protection layer: Cognito, WAF, CloudFront; included alongside `ci/inca-pipeline.yml` in the same child pipeline DAG |
| `ci/bootstrap.yml` | Child pipeline — manages IAM/OIDC roles, ECR repository, state backend |
| `scripts/ci/ci_terraform.sh` | Shell helpers sourced by apply jobs: plan artifact download and validation |
| `scripts/runner/` | Scripts embedded in the runner Docker image (not CI-only) |
| `tests/integration/` | Integration test scripts called by smoke test jobs |
| `ci/quality/.tflint.hcl` | tflint configuration (AWS plugin, compact format) |
| `ci/quality/.checkov.yaml` | Checkov skip rules with documented rationale |

---

## 3. Pipeline Architecture

### Two-Level Design: Parent + Child Pipelines

The parent pipeline in `.gitlab-ci.yml` does not run Terraform or tests itself. Its sole responsibility is to decide which child pipeline to trigger based on changed file paths and the `pipeline-action` input.

The application child pipeline is composed of two files included in a single `trigger:` block: `ci/inca-pipeline.yml` (INCA workflow + shared stages and variables) and `ci/api-security.yml` (API protection stacks). Because both files are included in the same trigger, all jobs share a common DAG and can reference each other via `needs:`.

```
.gitlab-ci.yml (parent)
│
├── trigger_runner_pipeline
│     └── ci/runner.yml
│
├── trigger_application_pipeline (single child pipeline, two files merged)
│     ├── ci/inca-pipeline.yml   — stages, variables, quality jobs, upload,
│     │                             validation, deployment, learner-sandbox
│     └── ci/api-security.yml    — Cognito, WAF, CloudFront
│
└── trigger_bootstrap_pipeline
      └── ci/bootstrap.yml
```

The parent uses `strategy: depend`, so its status reflects the child pipeline's outcome. Variables (`PIPELINE_ACTION`, `TARGET_STACK`, `CONFIRMATION`, `PARENT_PIPELINE_SOURCE`) are forwarded to children via `forward: yaml_variables: true pipeline_variables: true`.

### Parent Pipeline Stages

| Stage | Trigger jobs |
|---|---|
| `runner` | `trigger_runner_pipeline` |
| `orchestrate` | `trigger_application_pipeline`, `trigger_bootstrap_pipeline` |

The `runner` stage runs before `orchestrate`. In practice, runner image and application/bootstrap pipelines are independent — they are never triggered by the same set of changed files.

> **Important:** `trigger_runner_pipeline` and `trigger_bootstrap_pipeline` are both suppressed when `PIPELINE_ACTION` is `plan`, `apply`, or `destroy`. Only `trigger_application_pipeline` responds to manual operator actions.

### Child Pipeline Stages

| Child pipeline | Stages |
|---|---|
| `ci/runner.yml` | `auth` → `test` → `pre_publish` → `publish` |
| `ci/inca-pipeline.yml` + `ci/api-security.yml` | `validate` → `plan` → `apply` → `verify` → `destroy` |
| `ci/bootstrap.yml` | `validate` → `plan` → `apply` |

---

## 4. Terraform Stacks Covered

The application infrastructure pipeline manages these Terraform stacks:

| Stack | Path | Environments | Description |
|---|---|---|---|
| `upload-foundation` | `terraform/upload-foundation/` | `dev`, `main` | Upload API Gateway, prepare/complete Lambdas, S3 bucket, DynamoDB, EventBridge |
| `validation-foundation` | `terraform/validation-foundation/` | `dev`, `main` | ECS cluster (Fargate), validation task definition, VPC, security groups |
| `deployment-foundation` | `terraform/deployment-foundation/` | `dev` only | Deployment API Gateway, trigger-deployment Lambda, Step Functions, ECS deployment task |
| `cognito` | `terraform/cognito/` | `dev` only | Cognito User Pool, app client, test users, WAF association |
| `waf-foundation` | `terraform/waf-foundation/` | `dev` only | Regional WAF (eu-west-3): IP allowlist, geo-block, rate limit, OWASP rules |
| `cloudfront-foundation` | `terraform/cloudfront-foundation/` | `dev` only | CloudFront WAF (us-east-1) + 2 CloudFront distributions (upload + deployment APIs) |
| `learner-sandbox-roles` | `terraform/learner-sandbox-roles/` | `dev` only | IAM roles provisioned in learner AWS sandbox accounts |

The bootstrap pipeline manages:

| Stack | Path | Description |
|---|---|---|
| `gitlab-oidc-roles` | `terraform/gitlab-oidc-roles/` | GitLab OIDC IAM roles allowing the CI runner to authenticate with AWS |
| `ecr` | `terraform/ecr/` | ECR repository for the Terraform runner image |
| `state-backend` | `terraform/state-backend/` | S3 bucket + DynamoDB table for Terraform remote state |

---

## 5. Pipeline Inputs

### Available Inputs

Inputs are declared in `.gitlab-ci.yml` and exposed in the **Run pipeline** UI.

| Input | Default | Options | Purpose |
|---|---|---|---|
| `pipeline-action` | `auto` | `auto`, `plan`, `apply`, `destroy` | Controls which jobs appear in the pipeline |
| `target-stack` | `all` | `all`, `upload`, `validation`, `deployment`, `cognito`, `waf`, `cloudfront`, `learner-sandbox` | Scopes destroy jobs — ignored for `auto`, `plan`, `apply` |
| `confirmation` | _(empty)_ | Free text | Safety token required for `apply` and `destroy` — checked at job start |

> **Note:** `target-stack` does not scope plan or apply actions — those jobs are scoped by changed file paths. It only controls which stacks are destroyed when `pipeline-action=destroy`.

### Confirmation Tokens

The confirmation token is forwarded to every apply and destroy job. Each job checks it at the very first line of its script before any Terraform command runs.

| Action | Branch | Token required |
|---|---|---|
| `apply` | `dev` | `APPLY` |
| `apply` | `main` | `APPLY` |
| `destroy` | `dev` | `DESTROY-DEV` |
| `destroy` | `main` | `DESTROY-PROD` |
| `plan` | any | _(leave empty)_ |
| `auto` | any | _(leave empty)_ |

A wrong or missing token fails the job immediately with a message like:
```
Set confirmation=APPLY to confirm apply action
```

---

## 6. Path-Based Routing

### Which Child Pipeline Is Triggered

The parent pipeline has inline rules per trigger job. The parent triggers each child pipeline based on which files changed:

| Changed paths | Child pipeline triggered |
|---|---|
| `Dockerfile`, `config/**`, `scripts/runner/**`, `tests/fixtures/blueprints/**`, `ci/_templates.yml`, `ci/runner.yml`, `.gitlab-ci.yml` | `ci/runner.yml` |
| `Dockerfile`, `config/**`, `lambdas/**`, `scripts/**`, `tests/**`, any `terraform/*-foundation/**`, `terraform/cognito/**`, `terraform/learner-sandbox-roles/**`, `ci/inca-pipeline.yml`, `ci/api-security.yml`, or **any web-triggered pipeline** | `ci/inca-pipeline.yml` + `ci/api-security.yml` |
| `terraform/ecr/**`, `terraform/gitlab-oidc-roles/**`, `terraform/state-backend/**`, `ci/_templates.yml`, `ci/bootstrap.yml`, `.gitlab-ci.yml` | `ci/bootstrap.yml` |

> Changes to shared CI files (`.gitlab-ci.yml`, `ci/_templates.yml`) can trigger multiple child pipelines simultaneously.

> The application pipeline is **always triggered for web pipelines** (`$CI_PIPELINE_SOURCE == "web"`). This is how `apply` and `destroy` actions reach the child pipeline even when no files changed.

### Which Jobs Run Inside a Child Pipeline

Inside the application pipeline, each individual job has its own `rules:` defined in either `ci/inca-pipeline.yml` or `ci/api-security.yml`. For example, `plan_upload_dev` only runs when upload-related files change on the `dev` branch. This two-level filtering ensures that a change to `terraform/cognito/` does not trigger an upload plan.

The general rule logic per job:
- `PIPELINE_ACTION == "destroy"` or `PIPELINE_ACTION == "apply"` → **never** (these actions skip validate and plan entirely)
- `PIPELINE_ACTION == "plan"` → **always run** if on the correct branch
- Neither of the above → run **only if relevant files changed** on the correct branch

---

## 7. Operator Workflows

### Branch = Environment: A Hard Rule

The branch determines the environment. This is enforced in job `rules:` — it is not a convention.

| Branch | Environment |
|---|---|
| `dev` | `dev` |
| `main` or `master` | `main` (prod) |

It is not possible to apply or destroy the prod environment from the `dev` branch, even by setting variables manually. The rules will not expose those jobs.

---

### Push / Auto Workflow

Triggered by: a regular git push, or `pipeline-action=auto` from the UI.

**What runs:**

```
[validate stage]
  - Lambda unit tests (Python)
  - Ruff linting
  - terraform fmt -check
  - tflint (all stacks)
  - Checkov scan (all stacks)
  - terraform validate (per changed stack)

[plan stage]
  - terraform plan -out=tfplan (per changed stack/environment)
  - Saves plan artifact (expires in 1 hour)
```

**What does NOT run:** apply, verify, destroy stages.

The plan artifact is saved and consumed by a later explicit apply pipeline.

---

### Plan Workflow

Triggered by: `pipeline-action=plan` from the UI, on any branch.

Behavior is identical to push/auto: validate and plan stages run, plan artifacts are saved. No apply or destroy jobs appear.

Use this to force a fresh plan without pushing a new commit — for example, to reset the 1-hour artifact expiry window.

---

### Apply Workflow

Triggered by: `pipeline-action=apply` + `confirmation=APPLY` from the UI, **on dev or main branch**.

**What runs:**

```
[apply stage only]
  Each apply job independently:
  1. Checks confirmation token (fails immediately if wrong/missing)
  2. Downloads the plan artifact from the latest plan job on this branch
     via GitLab API: GET /api/v4/projects/:id/jobs/artifacts/:branch/download?job=:job_name
  3. Verifies PLAN_COMMIT_SHA matches current CI_COMMIT_SHA
  4. Runs: terraform apply -input=false tfplan
  5. (Some jobs) Exports dotenv artifact with Terraform outputs

[verify stage — runs automatically after successful apply]
  Smoke tests run for each stack that was successfully applied.
```

> The apply stage is only reachable from a **web-triggered pipeline** (`$PARENT_PIPELINE_SOURCE != "push"`). A push can never accidentally trigger an apply, even if `PIPELINE_ACTION=apply` were somehow set.

**Apply timeline:**

```
─── Push pipeline ─────────────────────────────────
  [validate] → [plan] → artifact saved (1 hour TTL)

─── Apply pipeline (triggered manually from UI) ────
  [apply] ← downloads artifact from plan pipeline
          ← verifies PLAN_COMMIT_SHA == CI_COMMIT_SHA
          ← terraform apply tfplan
  [verify] ← smoke tests run automatically
```

If the commit changed since the plan was generated, the apply fails with:
```
Plan commit <sha> does not match current HEAD <sha>. Push a new plan before applying.
```

If the plan artifact expired (>1 hour), the apply fails with instructions to run a new plan.

**Apply jobs expose Terraform outputs as dotenv artifacts** (valid for 1 day) which are consumed by downstream smoke test jobs:

| Apply job | Dotenv outputs |
|---|---|
| `apply_upload_dev` / `apply_upload_main` | `API_URL`, `UPLOAD_INTENTS_TABLE_NAME` |
| `apply_deployment_dev` | `DEPLOYMENT_API_URL`, `DEPLOYMENT_STATE_MACHINE_ARN`, `ECS_TASK_ROLE_ARN`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID` |
| `apply_cognito_dev` | `USER_POOL_ID`, `USER_POOL_CLIENT_ID` |
| `apply_waf_dev` | `WAF_WEB_ACL_ARN`, `WAF_LOG_GROUP_NAME` |
| `apply_cloudfront_dev` | `UPLOAD_CLOUDFRONT_DOMAIN`, `DEPLOYMENT_CLOUDFRONT_DOMAIN` |

---

### Destroy Workflow

Triggered by: `pipeline-action=destroy` + the correct confirmation token + `target-stack=<stack>` from the UI.

Destroy jobs start **automatically** when the pipeline is triggered — there is no manual click required in the UI beyond triggering the pipeline itself. The confirmation token is the only safety gate.

**Supported `target-stack` values and the jobs they expose:**

| `target-stack` | Branch | Jobs exposed |
|---|---|---|
| `upload` | `dev` | `destroy_upload_dev` |
| `upload` | `main` | `destroy_upload_main` |
| `validation` | `dev` | `destroy_validation_dev` |
| `validation` | `main` | `destroy_validation_main` |
| `deployment` | `dev` | `destroy_deployment_dev` |
| `cognito` | `dev` | `destroy_cognito_dev` |
| `waf` | `dev` | `destroy_waf_dev` |
| `cloudfront` | `dev` | `destroy_cloudfront_dev` |
| `learner-sandbox` | `dev` | `destroy_learner_sandbox_dev` |
| `all` | `dev` | All `dev` destroy jobs |
| `all` | `main` | `destroy_upload_main`, `destroy_validation_main` |

Each destroy job uses a `resource_group` lock to prevent concurrent destructive runs.

**Recommended destruction order** when tearing down a full `dev` environment — destroy dependents before their dependencies:

```
1. destroy_deployment_dev    (Step Functions, ECS cluster, Lambda)
2. destroy_cloudfront_dev    (CloudFront distributions, WAF CLOUDFRONT)
3. destroy_validation_dev    (ECS validation cluster, VPC)
4. destroy_upload_dev        (API Gateway, Lambdas, S3, DynamoDB)
5. destroy_cognito_dev       (User Pool)
6. destroy_waf_dev           (Regional WAF)
7. destroy_learner_sandbox_dev (IAM roles in sandbox accounts)
```

---

## 8. Plan / Apply Guardrails

### Application Infrastructure — Cross-Pipeline Guardrail

Plan and apply jobs run in **separate pipelines**. The apply job cannot access the plan artifact directly via `needs:` — instead it downloads it from the GitLab API.

**Plan pipeline** (`push` or `pipeline-action=plan`):
1. Runs `terraform plan -out=tfplan`
2. Records `PLAN_PIPELINE_ID=${CI_PIPELINE_ID}` and `PLAN_COMMIT_SHA=${CI_COMMIT_SHA}` in `plan-metadata.env`
3. Saves all files as a GitLab artifact expiring in **1 hour**

**Apply pipeline** (`pipeline-action=apply`), via `download_and_validate_plan_artifact` in `scripts/ci/ci_terraform.sh`:
1. Downloads artifact ZIP from:
   ```
   GET /api/v4/projects/:id/jobs/artifacts/:branch/download?job=:job_name
   ```
2. Extracts into workspace
3. Sources `plan-metadata.env`
4. Checks `PLAN_COMMIT_SHA == CI_COMMIT_SHA` (fails if different)
5. Runs `terraform apply -input=false tfplan`

> There is no `PLAN_PIPELINE_ID` check in cross-pipeline mode — by design, the two pipelines have different IDs.

### Bootstrap Foundation — Same-Pipeline Guardrail

Apply jobs in `ci/bootstrap.yml` are `when: manual` and run in the **same pipeline** as their plan job. The `validate_plan_artifacts` helper (also in `scripts/ci/ci_terraform.sh`) checks **both**:

- `PLAN_PIPELINE_ID == CI_PIPELINE_ID`
- `PLAN_COMMIT_SHA == CI_COMMIT_SHA`

Bootstrap plan artifacts expire in **7 days** (vs 1 hour for application stacks), because bootstrap changes are rare and the plan/apply cycle may span a longer review window.

### Plan Artifact Contents per Stack

| Stack | Artifact files |
|---|---|
| `upload-foundation` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt`, `prepare-template-upload.zip`, `complete-template-upload.zip` |
| `validation-foundation` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt` |
| `deployment-foundation` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt`, `trigger-deployment.zip` |
| `cognito` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt` |
| `waf-foundation` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt` |
| `cloudfront-foundation` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt` |
| `learner-sandbox-roles` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt` |
| `gitlab-oidc-roles` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt` |
| `ecr` | `tfplan`, `tfplan.txt`, `tfplan.json`, `plan-metadata.env`, `plan-metadata.txt` |

The Lambda ZIP files (`.zip`) included in upload-foundation and deployment-foundation artifacts are built by Terraform's `archive_file` data source during `terraform plan` and must travel with the plan to be applied as-is.

### Terraform Plan Summary in Merge Requests

Each plan job declares `reports: terraform: tfplan.json`. GitLab uses this to render a native plan diff widget directly in the merge request, showing the number of resources to add/change/destroy without reading raw plan output.

---

## 9. Job Reference: Runner Image Pipeline

**File:** `ci/runner.yml`

This pipeline only triggers when runner-domain files change (see [Path-Based Routing](#6-path-based-routing)). It does **not** run for `pipeline-action=plan/apply/destroy`.

| Job | Stage | Trigger condition | Purpose |
|---|---|---|---|
| `verify_runner_aws_oidc_authentication` | `auth` | Any runner file change | Validates OIDC authentication to AWS. `allow_failure: false` — blocks publish if it fails |
| `check_runner_shell_scripts_syntax` | `test` | Any runner file change | `bash -n scripts/runner/*.sh scripts/ci/*.sh` — fast syntax check |
| `test_runner_offline_provider_supported_package` | `test` | Any runner file change | Validates a valid Terraform package against the offline provider mirror |
| `test_runner_offline_provider_unsupported_package` | `test` | Any runner file change | Validates that an unsupported provider fails with a clear error |
| `check_runner_image_in_ecr` | `pre_publish` | `dev` or `main`/`master` branch + runner file changes | Checks ECR for an existing image with tag `${CI_COMMIT_SHA}`. If found, retags mutable tags and sets `SKIP_KANIKO=true`. Otherwise sets `SKIP_KANIKO=false`. |
| `publish_runner_image_to_ecr` | `publish` | `dev` or `main`/`master` branch + runner file changes | If `SKIP_KANIKO=false`, builds the image with Kaniko and pushes to ECR. If `SKIP_KANIKO=true`, skips the build (image already published). |

**Idempotency:** `check_runner_image_in_ecr` makes publishing idempotent. If the pipeline re-runs on the same commit (e.g., after a transient failure), Kaniko is skipped and only mutable tags (`:dev`, `:main`, `:latest`) are updated via `ecr:PutImage`.

**Kaniko:** The publish job uses `gcr.io/kaniko-project/executor:debug` to avoid `docker:dind` instability on shared runners. OIDC credentials are passed to Kaniko via a web identity token file at `/kaniko/web-identity-token`.

---

## 10. Job Reference: Application Infrastructure Pipeline

**Files:** `ci/inca-pipeline.yml` (INCA workflow + shared stages/variables/quality jobs) and `ci/api-security.yml` (Cognito, WAF, CloudFront), both included in a single child pipeline DAG.

### Validate Stage

Runs on `push` or `pipeline-action=plan`. Skipped when `pipeline-action=apply` or `pipeline-action=destroy`.

Cross-cutting quality jobs (defined in `ci/inca-pipeline.yml`, cover all stacks):

| Job | Changed paths that activate it | Purpose |
|---|---|---|
| `check_terraform_format` | Any infra or CI change | `terraform fmt -check -recursive terraform` across all stacks |
| `lint_terraform` | Any infra or CI change | `tflint` with AWS plugin, iterating all `terraform/*/` subdirectories that contain `main.tf`. Uses a CI cache keyed on `tflint-aws-v0.40.0`. |
| `scan_terraform` | Any infra or CI change | Checkov security scan using `ci/quality/.checkov.yaml`. `allow_failure: true` while skip baseline is reviewed. |

Domain-specific validate jobs:

| Job | File | Changed paths that activate it | Purpose |
|---|---|---|---|
| `test_upload_lambdas` | `ci/inca-pipeline.yml` | Upload-related files | Python `unittest` for prepare-upload and complete-upload Lambdas |
| `lint_upload_lambdas` | `ci/inca-pipeline.yml` | Upload-related files | Ruff linting on upload Lambda source |
| `validate_upload_terraform` | `ci/inca-pipeline.yml` | Upload-related files | `terraform validate` on `terraform/upload-foundation/` |
| `test_deployment_lambdas` | `ci/inca-pipeline.yml` | `lambdas/trigger-deployment/**`, deployment-related files | Python `unittest` for trigger-deployment Lambda |
| `lint_deployment_lambdas` | `ci/inca-pipeline.yml` | Same as above | Ruff linting on deployment Lambda source |
| `validate_deployment_terraform` | `ci/inca-pipeline.yml` | Deployment-related files | `terraform validate` on `terraform/deployment-foundation/` |
| `validate_validation_terraform` | `ci/inca-pipeline.yml` | Validation-related files | `terraform validate` on `terraform/validation-foundation/` |
| `validate_learner_sandbox_terraform` | `ci/inca-pipeline.yml` | `terraform/learner-sandbox-roles/**` | `terraform validate` on `terraform/learner-sandbox-roles/` |
| `validate_cognito_terraform` | `ci/api-security.yml` | `terraform/cognito/**` | `terraform validate` on `terraform/cognito/` |
| `validate_waf_terraform` | `ci/api-security.yml` | `terraform/waf-foundation/**` | `terraform validate` on `terraform/waf-foundation/` |
| `validate_cloudfront_terraform` | `ci/api-security.yml` | `terraform/cloudfront-foundation/**` | `terraform validate` on `terraform/cloudfront-foundation/` |

All `validate_*` jobs run `terraform init -backend=false` (no remote state access required).

### Plan Stage

Runs on `push` or `pipeline-action=plan`. Skipped when `pipeline-action=apply` or `pipeline-action=destroy`. Each plan job `needs:` its corresponding validate jobs (all `optional: true` — the plan runs even if a validate job was skipped).

| Job | File | Branch | IAM role used | Runner SHA required |
|---|---|---|---|---|
| `plan_upload_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-upload-dev` | No |
| `plan_upload_main` | `ci/inca-pipeline.yml` | `main`/`master` | `inca-auto-deployer-gitlab-upload-main` | No |
| `plan_validation_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-validation-dev` | Yes — resolves `:dev` SHA from ECR |
| `plan_validation_main` | `ci/inca-pipeline.yml` | `main`/`master` | `inca-auto-deployer-gitlab-validation-main` | Yes — resolves `:main` SHA from ECR |
| `plan_deployment_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-deployment-dev` | Yes — resolves `:dev` SHA from ECR |
| `plan_learner_sandbox_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-learner-sandbox` | No |
| `plan_cognito_dev` | `ci/api-security.yml` | `dev` | `inca-auto-deployer-gitlab-cognito-dev` | No |
| `plan_waf_dev` | `ci/api-security.yml` | `dev` | `inca-auto-deployer-gitlab-waf-dev` | No |
| `plan_cloudfront_dev` | `ci/api-security.yml` | `dev` | `inca-auto-deployer-gitlab-cloudfront-dev` | No |

**Runner SHA resolution** (validation and deployment plan jobs):

Before running `terraform plan`, these jobs resolve the actual commit SHA of the runner image in ECR:

```bash
RUNNER_SHA=$(aws ecr describe-images \
  --repository-name inca-terraform-runner \
  --image-ids imageTag=dev \
  --query 'imageDetails[0].imageTags[]' \
  --output text | tr '\t' '\n' | grep -E '^[0-9a-f]{40}$' | head -1)
```

This ensures `TF_VAR_validation_runner_image_tag` / `TF_VAR_deployment_runner_image_tag` is an immutable 40-character SHA, not a mutable tag like `:dev` that could silently drift between plan and apply. If no SHA is found (runner image pipeline not yet run), the plan fails immediately with an explicit error.

### Apply Stage

Only runs when `pipeline-action=apply && $PARENT_PIPELINE_SOURCE != "push" && CI_COMMIT_BRANCH == <expected>`.

The `$PARENT_PIPELINE_SOURCE != "push"` guard ensures that apply can **never** be triggered by a push — only by a manually triggered web pipeline.

All apply jobs:
- Check the confirmation token first
- Use `download_and_validate_plan_artifact` to fetch and verify the plan
- Use a `resource_group` to prevent concurrent applies on the same stack
- Register a GitLab environment (`dev/<stack>` or `main/<stack>`)

| Job | File | Branch | IAM role used | Exports dotenv |
|---|---|---|---|---|
| `apply_upload_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-upload-dev` | `API_URL`, `UPLOAD_INTENTS_TABLE_NAME` |
| `apply_upload_main` | `ci/inca-pipeline.yml` | `main`/`master` | `inca-auto-deployer-gitlab-upload-main` | `API_URL`, `UPLOAD_INTENTS_TABLE_NAME` |
| `apply_validation_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-validation-dev` | No |
| `apply_validation_main` | `ci/inca-pipeline.yml` | `main`/`master` | `inca-auto-deployer-gitlab-validation-main` | No |
| `apply_deployment_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-deployment-dev` | `DEPLOYMENT_API_URL`, `DEPLOYMENT_STATE_MACHINE_ARN`, `ECS_TASK_ROLE_ARN`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID` |
| `apply_learner_sandbox_dev` | `ci/inca-pipeline.yml` | `dev` | `inca-auto-deployer-gitlab-learner-sandbox` | No |
| `apply_cognito_dev` | `ci/api-security.yml` | `dev` | `inca-auto-deployer-gitlab-cognito-dev` | `USER_POOL_ID`, `USER_POOL_CLIENT_ID` |
| `apply_waf_dev` | `ci/api-security.yml` | `dev` | `inca-auto-deployer-gitlab-waf-dev` | `WAF_WEB_ACL_ARN`, `WAF_LOG_GROUP_NAME` |
| `apply_cloudfront_dev` | `ci/api-security.yml` | `dev` | `inca-auto-deployer-gitlab-cloudfront-dev` | `UPLOAD_CLOUDFRONT_DOMAIN`, `DEPLOYMENT_CLOUDFRONT_DOMAIN` |

Dotenv artifacts expire after **1 day** and are consumed by downstream smoke test jobs via `needs: artifacts: true`.

### Verify Stage (Smoke Tests)

Smoke tests run **automatically** (`when: on_success`) after a successful apply, only when `pipeline-action=apply`. They run `allow_failure: false`.

| Job | File | Depends on | Branch | Test script | Wait timeout |
|---|---|---|---|---|---|
| `smoke_test_upload_dev` | `ci/inca-pipeline.yml` | `apply_upload_dev` | `dev` | `tests/integration/test_upload_foundation_flow.sh` | — |
| `smoke_test_validation_dev` | `ci/inca-pipeline.yml` | `apply_validation_dev` | `dev` | `tests/integration/test_validation_foundation_flow.sh` | 180 s |
| `smoke_test_deployment_dev` | `ci/inca-pipeline.yml` | `apply_deployment_dev` + `apply_upload_dev` | `dev` | `tests/integration/test_deployment_foundation_flow.sh` | 300 s |
| `smoke_test_upload_main` | `ci/inca-pipeline.yml` | `apply_upload_main` | `main`/`master` | `tests/integration/test_upload_foundation_flow.sh` | — |
| `smoke_test_validation_main` | `ci/inca-pipeline.yml` | `apply_validation_main` | `main`/`master` | `tests/integration/test_validation_foundation_flow.sh` | 180 s |

`smoke_test_validation_*` reads the upload foundation Terraform state directly to obtain `API_URL` and `UPLOAD_INTENTS_TABLE_NAME` (it uses the upload role, not the validation role).

`smoke_test_deployment_dev` receives its environment variables from the dotenv artifacts of both `apply_upload_dev` and `apply_deployment_dev`.

### Destroy Stage

Destroy jobs run automatically when the pipeline is triggered with `pipeline-action=destroy`. Each job checks the confirmation token before any Terraform command.

| Job | File | Stack | Branch | Confirmation required | `resource_group` |
|---|---|---|---|---|---|
| `destroy_upload_dev` | `ci/inca-pipeline.yml` | `upload-foundation` | `dev` | `DESTROY-DEV` | `terraform-upload-dev` |
| `destroy_upload_main` | `ci/inca-pipeline.yml` | `upload-foundation` | `main`/`master` | `DESTROY-PROD` | `terraform-upload-main` |
| `destroy_validation_dev` | `ci/inca-pipeline.yml` | `validation-foundation` | `dev` | `DESTROY-DEV` | `terraform-validation-dev` |
| `destroy_validation_main` | `ci/inca-pipeline.yml` | `validation-foundation` | `main`/`master` | `DESTROY-PROD` | `terraform-validation-main` |
| `destroy_deployment_dev` | `ci/inca-pipeline.yml` | `deployment-foundation` | `dev` | `DESTROY-DEV` | `terraform-deployment-dev` |
| `destroy_learner_sandbox_dev` | `ci/inca-pipeline.yml` | `learner-sandbox-roles` | `dev` | `DESTROY-DEV` | `terraform-learner-sandbox` |
| `destroy_cognito_dev` | `ci/api-security.yml` | `cognito` | `dev` | `DESTROY-DEV` | `terraform-cognito-dev` |
| `destroy_waf_dev` | `ci/api-security.yml` | `waf-foundation` | `dev` | `DESTROY-DEV` | `terraform-waf-dev` |
| `destroy_cloudfront_dev` | `ci/api-security.yml` | `cloudfront-foundation` | `dev` | `DESTROY-DEV` | `terraform-cloudfront-dev` |

---

## 11. Job Reference: Bootstrap Pipeline

**File:** `ci/bootstrap.yml`

This pipeline is separate from regular application delivery and is intentionally low-frequency. It manages the resources that allow GitLab CI to work at all (OIDC roles, ECR repository, remote state bucket).

Plan artifacts expire in **7 days** (not 1 hour like application stacks).

Apply jobs are `when: manual` (require a click in the GitLab UI) and use the **same-pipeline guardrail** (checks both `PLAN_PIPELINE_ID` and `PLAN_COMMIT_SHA`).

Destroy is intentionally absent — bootstrap resources must be decommissioned manually to prevent accidental loss of CI/CD access.

| Job | Stage | Purpose |
|---|---|---|
| `check_terraform_format_bootstrap` | `validate` | `terraform fmt -check -recursive terraform` |
| `lint_terraform_bootstrap` | `validate` | `tflint` across all stacks (with `ci/quality/.tflint.hcl` config) |
| `scan_terraform_bootstrap` | `validate` | Checkov scan using `ci/quality/.checkov.yaml` (`allow_failure: true`) |
| `validate_gitlab_oidc_roles_terraform` | `validate` | `terraform validate` on `terraform/gitlab-oidc-roles/` |
| `validate_runner_ecr_repository_terraform` | `validate` | `terraform validate` on `terraform/ecr/` |
| `validate_terraform_state_backend_terraform` | `validate` | `terraform validate` on `terraform/state-backend/` |
| `plan_gitlab_oidc_roles` | `plan` | Plan IAM/OIDC roles — runs on `dev`/`main`/`master` only |
| `plan_runner_ecr_repository` | `plan` | Plan ECR repository — runs on `dev`/`main`/`master` only |
| `apply_gitlab_oidc_roles` | `apply` | `when: manual` — applies IAM/OIDC roles after same-pipeline guardrail check |
| `apply_runner_ecr_repository` | `apply` | `when: manual` — applies ECR repository after same-pipeline guardrail check |

Both `apply_gitlab_oidc_roles` and `apply_runner_ecr_repository` use the `inca-auto-deployer-gitlab-oidc-admin` role and share the `terraform-foundation` resource group.

---

## 12. Authentication Model

### GitLab OIDC Flow

No long-lived AWS access keys are stored in the pipeline. All AWS interactions use temporary credentials obtained via GitLab OIDC.

```
1. GitLab issues an OIDC token (GITLAB_OIDC_TOKEN) for the job.
   → Token audience: https://gitlab.revolve.team

2. Job calls: aws sts assume-role-with-web-identity
   → --role-arn ${TF_ROLE_ARN}
   → --role-session-name "GitLabRunner-${CI_PROJECT_ID}-${CI_PIPELINE_ID}"
   → --web-identity-token ${GITLAB_OIDC_TOKEN}
   → --duration-seconds 3600

3. AWS validates the token against the GitLab OIDC provider.

4. AWS returns temporary credentials (valid 1 hour).

5. Job exports AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN.

6. Subsequent AWS/Terraform calls use these credentials.
```

### OIDC Templates

Defined in `ci/_templates.yml`:

**`.terraform_base`** — sets the Terraform Docker image (`hashicorp/terraform:1.14.7`) and disables services.

**`.terraform_oidc_base`** — extends `.terraform_base` and declares the `GITLAB_OIDC_TOKEN` id token.

**`.oidc_assume_role`** — `before_script` that installs `aws-cli` (via `apk`), runs `assume-role-with-web-identity`, and exports the resulting credentials. Requires `TF_ROLE_ARN` to be set at job level.

Each job sets `TF_ROLE_ARN` to the appropriate role for its stack and environment:
```yaml
apply_upload_dev:
  extends:
    - .terraform_oidc_base
    - .oidc_assume_role
  variables:
    TF_ROLE_ARN: "${AWS_ROLE_ARN_UPLOAD_DEV}"
```

The runner image pipeline uses its own `.aws_oidc_base` template (AWS CLI image, not Terraform) with the same OIDC exchange logic.

### IAM Role Split

| Variable | Role ARN | Used by |
|---|---|---|
| `AWS_ROLE_ARN` | `inca-auto-deployer-gitlab-ecr-push` | Runner image publication (fallback) |
| `AWS_ROLE_ARN_RUNNER` | _(override, empty by default)_ | Runner image publication (takes precedence over `AWS_ROLE_ARN` if set) |
| `AWS_ROLE_ARN_UPLOAD_DEV` | `inca-auto-deployer-gitlab-upload-dev` | Upload plan/apply/destroy on `dev` |
| `AWS_ROLE_ARN_UPLOAD_MAIN` | `inca-auto-deployer-gitlab-upload-main` | Upload plan/apply/destroy on `main` |
| `AWS_ROLE_ARN_VALIDATION_DEV` | `inca-auto-deployer-gitlab-validation-dev` | Validation plan/apply/destroy on `dev` |
| `AWS_ROLE_ARN_VALIDATION_MAIN` | `inca-auto-deployer-gitlab-validation-main` | Validation plan/apply/destroy on `main` |
| `AWS_ROLE_ARN_DEPLOYMENT_DEV` | `inca-auto-deployer-gitlab-deployment-dev` | Deployment foundation plan/apply/destroy on `dev` |
| `AWS_ROLE_ARN_COGNITO_DEV` | `inca-auto-deployer-gitlab-cognito-dev` | Cognito plan/apply/destroy on `dev` |
| `AWS_ROLE_ARN_WAF_DEV` | `inca-auto-deployer-gitlab-waf-dev` | WAF foundation plan/apply/destroy on `dev` |
| `AWS_ROLE_ARN_CLOUDFRONT_DEV` | `inca-auto-deployer-gitlab-cloudfront-dev` | CloudFront foundation plan/apply/destroy on `dev` |
| `AWS_ROLE_ARN_LEARNER_SANDBOX` | `inca-auto-deployer-gitlab-learner-sandbox` | Learner sandbox roles plan/apply/destroy |
| `AWS_ROLE_ARN_GITLAB_OIDC_ADMIN` | `inca-auto-deployer-gitlab-oidc-admin` | Bootstrap pipeline: IAM/OIDC roles and ECR repository |

All these roles are provisioned by `terraform/gitlab-oidc-roles/` and trust `gitlab.revolve.team` as the OIDC provider.

---

## 13. Runner Image

### Image Content

Built from `alpine:3.21` via `Dockerfile`.

Installed tools: `aws-cli`, `bash`, `ca-certificates`, `curl`, `git`, `jq`, `unzip`, `zip`, `terraform` (downloaded separately from releases.hashicorp.com).

Build arguments:

| Argument | Purpose |
|---|---|
| `TERRAFORM_VERSION` | Terraform version baked into the image (currently `1.14.7`) |
| `TERRAFORM_AWS_PROVIDER_VERSION` | AWS provider version baked into the offline provider mirror (currently `5.100.0`) |

Scripts from `scripts/runner/` are copied to `/app/scripts/`. Working directory: `/workspace`. Entrypoint: `/bin/bash`.

### Idempotency Check Before Build

Before Kaniko runs, `check_runner_image_in_ecr` queries ECR for an image tagged with the current `${CI_COMMIT_SHA}`:

- **Found:** the image was already built for this commit. The job retags mutable tags (`:dev` / `:main` / `:latest`) via `ecr:PutImage` and sets `SKIP_KANIKO=true`.
- **Not found:** sets `SKIP_KANIKO=false` and the Kaniko build proceeds.

This makes re-running a pipeline on the same commit fast and safe.

### ECR Tag Strategy

| Branch | Tags published |
|---|---|
| `dev` | `:dev`, `:<CI_COMMIT_SHA>`, `:<CI_COMMIT_REF_SLUG>` |
| `main` / `master` | `:main`, `:latest`, `:<CI_COMMIT_SHA>`, `:<CI_COMMIT_REF_SLUG>` |

Immutable tag: `:<CI_COMMIT_SHA>` (40-char hex). Mutable tags: `:dev`, `:main`, `:latest`.

Plan jobs for validation and deployment stacks always resolve and use the immutable SHA tag, not `:dev` or `:main`.

### Local Build and Verification

```bash
docker build \
  --build-arg TERRAFORM_VERSION=1.14.7 \
  --build-arg TERRAFORM_AWS_PROVIDER_VERSION=5.100.0 \
  -t inca-terraform-runner:local .

# Verify tools
docker run --rm inca-terraform-runner:local -lc "terraform version"
docker run --rm inca-terraform-runner:local -lc "aws --version"

# Test validation script on a fixture
docker run --rm \
  -v "$(pwd):/workspace" \
  inca-terraform-runner:local \
  /app/scripts/validate_upload.sh /workspace/examples/sample-lab
```

---

## 14. Environment Injection and Variable Files

### Variable File Pattern

Each stack uses explicit variable files to keep environment resolution deterministic:

| Stack | Dev | Main |
|---|---|---|
| `upload-foundation` | `dev.tfvars` + `backend-dev.hcl` | `main.tfvars` + `backend-main.hcl` |
| `validation-foundation` | `dev.tfvars` + `backend-dev.hcl` | `main.tfvars` + `backend-main.hcl` |
| `deployment-foundation` | `dev.tfvars` + `backend-dev.hcl` | _(not deployed to main)_ |
| `cognito` | `dev.tfvars` + `backend-dev.hcl` | _(not deployed to main)_ |
| `waf-foundation` | `dev.tfvars` + `backend-dev.hcl` | _(not deployed to main)_ |
| `cloudfront-foundation` | `dev.tfvars` + `backend-dev.hcl` | _(not deployed to main)_ |
| `learner-sandbox-roles` | `dev.tfvars` + `backend-dev.hcl` | _(not deployed to main)_ |
| `gitlab-oidc-roles` | `shared.tfvars` + `backend.hcl` | (shared, no env split) |

### TF_VAR_environment

For stacks that use an `environment` Terraform variable, the plan job injects it explicitly:

```yaml
variables:
  TF_VAR_environment: "dev"   # or "main"
```

This prevents Terraform from falling back to a default and accidentally managing the wrong environment's naming.

---

## 15. CI/CD Variables

| Variable | Defined in | Purpose |
|---|---|---|
| `AWS_ACCOUNT_ID` | `ci/runner.yml` | AWS account ID — used to build ECR registry URL |
| `AWS_REGION` | all child pipelines | Default AWS region for all API calls (`eu-west-3`) |
| `AWS_ROLE_ARN` | `ci/runner.yml` | Fallback ECR push role for runner image publication |
| `AWS_ROLE_ARN_RUNNER` | `ci/runner.yml` | Override ECR push role (takes precedence when non-empty) |
| `AWS_ROLE_ARN_UPLOAD_DEV` | `ci/inca-pipeline.yml` | Upload deployment role on `dev` |
| `AWS_ROLE_ARN_UPLOAD_MAIN` | `ci/inca-pipeline.yml` | Upload deployment role on `main` |
| `AWS_ROLE_ARN_VALIDATION_DEV` | `ci/inca-pipeline.yml` | Validation deployment role on `dev` |
| `AWS_ROLE_ARN_VALIDATION_MAIN` | `ci/inca-pipeline.yml` | Validation deployment role on `main` |
| `AWS_ROLE_ARN_DEPLOYMENT_DEV` | `ci/inca-pipeline.yml` | Deployment foundation role on `dev` |
| `AWS_ROLE_ARN_COGNITO_DEV` | `ci/inca-pipeline.yml` | Cognito role on `dev` (consumed by `ci/api-security.yml`) |
| `AWS_ROLE_ARN_WAF_DEV` | `ci/inca-pipeline.yml` | WAF foundation role on `dev` (consumed by `ci/api-security.yml`) |
| `AWS_ROLE_ARN_CLOUDFRONT_DEV` | `ci/inca-pipeline.yml` | CloudFront foundation role on `dev` (consumed by `ci/api-security.yml`) |
| `AWS_ROLE_ARN_LEARNER_SANDBOX` | `ci/inca-pipeline.yml` | Learner sandbox roles role |
| `AWS_ROLE_ARN_GITLAB_OIDC_ADMIN` | `ci/bootstrap.yml` | Admin role for bootstrap pipeline |
| `ECR_REPOSITORY` | `ci/runner.yml` | ECR repository name (`inca-terraform-runner`) |
| `TERRAFORM_VERSION` | `ci/runner.yml` | Terraform version in runner image |
| `TERRAFORM_AWS_PROVIDER_VERSION` | `ci/runner.yml` | AWS provider version in offline mirror |
| `TF_ROLE_ARN` | per job (not global) | Role ARN consumed by `.oidc_assume_role`; set individually per job |
| `PIPELINE_ACTION` | parent pipeline input | Forwarded from `pipeline-action` input |
| `TARGET_STACK` | parent pipeline input | Forwarded from `target-stack` input |
| `CONFIRMATION` | parent pipeline input | Forwarded from `confirmation` input |
| `PARENT_PIPELINE_SOURCE` | parent pipeline | Captures `$CI_PIPELINE_SOURCE` from the parent; used by apply rules to block push-triggered applies |

`TF_ROLE_ARN` is not a global variable. It is set at job level so that the shared `.oidc_assume_role` template can serve all jobs with different roles.

`CONFIRMATION` is forwarded via `forward: yaml_variables: true` from parent to child. Each apply/destroy job checks it at the first line of its script.

`PARENT_PIPELINE_SOURCE` is captured in the parent pipeline and forwarded to children, preserving the original trigger source. This is how child apply rules can distinguish a web trigger from a push trigger, even though the child pipeline's own `CI_PIPELINE_SOURCE` is always `parent_pipeline`.

---

## 16. GitLab Environments

| Environment name | Jobs registered |
|---|---|
| `dev/upload` | `apply_upload_dev`, `destroy_upload_dev` |
| `dev/validation` | `apply_validation_dev`, `destroy_validation_dev` |
| `dev/deployment` | `apply_deployment_dev`, `destroy_deployment_dev` |
| `dev/cognito` | `apply_cognito_dev`, `destroy_cognito_dev` |
| `dev/waf` | `apply_waf_dev`, `destroy_waf_dev` |
| `dev/cloudfront` | `apply_cloudfront_dev`, `destroy_cloudfront_dev` |
| `dev/learner-sandbox` | `apply_learner_sandbox_dev`, `destroy_learner_sandbox_dev` |
| `main/upload` | `apply_upload_main`, `destroy_upload_main` |
| `main/validation` | `apply_validation_main`, `destroy_validation_main` |
| `foundation` | `apply_gitlab_oidc_roles`, `apply_runner_ecr_repository` |

Destroy jobs set `action: stop` on their environment. Recommended GitLab protections before relying on manual apply in regular operations:
- Protect the `main` branch (restrict who can push)
- Protect `main/*` environments to control who can trigger manual jobs
- Review CI/CD variable visibility (mark sensitive role ARNs as protected)

---

## 17. Quality Configuration

### tflint (`ci/quality/.tflint.hcl`)

- Plugin: `terraform-linters/tflint-ruleset-aws` (cached under `.tflint.d/`)
- Format: compact
- Applied to every `terraform/*/` subdirectory that contains a `main.tf`

### Checkov (`ci/quality/.checkov.yaml`)

Runs with `framework: terraform` and `directory: terraform`. The following checks are permanently skipped with documented rationale:

| Check | Reason |
|---|---|
| `CKV_AWS_18` | No S3 server access log bucket — CloudTrail covers audit needs |
| `CKV_AWS_144` | No cross-region replication — single-region deployment, no DR scope |
| `CKV_AWS_21` | MFA delete cannot be enabled via Terraform (requires root credentials via S3 API) |
| `CKV_AWS_28` | DynamoDB PITR not needed — upload intents have a short lifecycle |
| `CKV2_AWS_118` | DynamoDB deletion protection disabled — destroy flow must remove the table cleanly |
| `CKV_AWS_117` | Lambda not in VPC — would require NAT Gateway; Lambdas use least-privilege IAM instead |
| `CKV_AWS_116` | No Lambda DLQ — API Gateway invocation is synchronous; failures surface as HTTP errors |
| `CKV_AWS_115` | No Lambda reserved concurrency — throttling managed at API Gateway stage level |
| `CKV_AWS_272` | No Lambda code-signing — provenance is guaranteed by the CI plan-metadata guardrail |
| `CKV_AWS_50` | Lambda X-Ray not enabled — observability via CloudWatch Logs is sufficient at this scale |
| `CKV2_AWS_29` | No API Gateway v2 access log — Lambda CloudWatch logs already cover request tracing |
| `CKV2_AWS_31` | WAF not attached to API Gateway — WAF is applied at the CloudFront layer |
| `CKV_AWS_158` | CloudWatch Logs not KMS-encrypted — no per-region CMK provisioned; AWS managed encryption used |
| `CKV_AWS_65` | ECS Container Insights disabled — cost control; CloudWatch task logs suffice |
| `CKV_AWS_25` | Security groups allow unrestricted egress — required for VPC interface endpoints on port 443 |
| `CKV_AWS_86` | CloudFront access logs disabled — WAF logs already capture security-relevant traffic |
| `CKV_AWS_310` | No CloudFront default root object — distributions front API Gateway, not static websites |

---

## 18. Known Limitations

- **Plan artifact TTL:** Application stack plan artifacts expire after 1 hour. An apply triggered more than 1 hour after the plan will fail and require a new plan.
- **No `main` coverage for most stacks:** `deployment-foundation`, `cognito`, `waf-foundation`, `cloudfront-foundation`, and `learner-sandbox-roles` currently only have CI jobs for the `dev` branch. Extending to `main` requires adding the corresponding rules, roles, and variable files.
- **Checkov `allow_failure: true`:** The security scan will not block pipelines until all intentional skips are reviewed and the flag is hardened to `false`.
- **No docs-only pipeline:** Documentation changes trigger the full application infrastructure pipeline (or no pipeline). A lightweight docs-only job does not exist.
- **No cross-environment promotion model:** There is no automated promotion from `dev` to `main`. The operator must manually trigger an apply pipeline on the `main` branch.
- **No GitLab approval workflow:** Beyond the manual pipeline trigger, the confirmation token, and the `when: manual` button (bootstrap only), there is no multi-person approval gate.
