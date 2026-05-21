# Validation Flow Architecture

Related diagram:

- [Validation flow architecture diagram](validation-flow-architecture.png)

## Objective

This document describes the current validation flow implemented in the repository, the operational constraints of that flow, and the tests currently in place to protect it.

The validation flow is built on top of the existing upload flow and is responsible for:

- reacting automatically after a Terraform ZIP upload is completed
- running Terraform validation in an isolated ECS Fargate task
- persisting the validation outcome in DynamoDB
- keeping the runtime compatible with private subnets and no outbound Internet access

## Current Lifecycle

The current user-visible lifecycle for an upload intent is:

- `PENDING`
- `UPLOADED`
- `VALIDATING`
- `VALIDATED`
- `VALIDATION_FAILED`

Current behavior:

1. `prepare` creates the DynamoDB item with `status = PENDING`
2. the ZIP is uploaded to `uploads/raw/<template_id>/<version_id>.zip`
3. `complete` verifies the object with `HeadObject`
4. `complete` updates the item to `status = UPLOADED`
5. S3 emits an object-created event to EventBridge
6. EventBridge triggers `ecs:RunTask` on the validation runner
7. the validation runner updates the item to `VALIDATING`
8. the runner downloads the ZIP, extracts it, and validates the Terraform package
9. the runner updates the item to `VALIDATED` or `VALIDATION_FAILED`

## Current Architecture

The validation flow currently relies on the following sequence:

- `S3` stores the raw uploaded ZIP package
- `EventBridge` receives the native `Object Created` event from the raw upload bucket
- an EventBridge rule filters only the raw ZIP uploads for the current environment
- the EventBridge target launches an `ECS Fargate` task
- the task runs `scripts/validate_upload.sh`
- the task reads the package from `S3`, writes state to `DynamoDB`, and writes execution logs to `CloudWatch Logs`

The validation workload runs in a dedicated `terraform/validation-foundation/` stack.

## Runtime And Network Model

The current design baseline is:

- upload and validation remain two separate lifecycle stages
- `prepare` remains the only entry point creating a new upload intent
- `UPLOADED` remains a distinct state before validation starts
- the validation flow is triggered automatically through `S3 -> EventBridge -> ECS RunTask`
- the validation workload runs on ECS Fargate, not in Lambda
- Step Functions are not part of the current implementation

The runtime executes in private subnets and does not rely on outbound Internet access once the task is running.

The private-network target currently uses VPC endpoints for:

- `S3`
- `DynamoDB`
- `ECR API`
- `ECR DKR`
- `CloudWatch Logs`

The validation stack can bootstrap its own private VPC resources for isolated environments. That network layer can later be adapted or removed if the flow is integrated into a broader platform VPC.

## Event Contract

The current implementation relies on the native S3 object-created event routed through EventBridge.

The EventBridge rule filters on:

- source: `aws.s3`
- detail-type: `Object Created`
- bucket name: the raw upload bucket for the current environment
- object key prefix: `uploads/raw/`
- object key suffix: `.zip`

The runner derives `template_id` and `version_id` from the object key format:

- `uploads/raw/<template_id>/<version_id>.zip`

The ECS target payload currently carries at least:

- `bucket`
- `key`
- `size`
- `etag`
- `region`

## Current DynamoDB Model

The table key structure remains:

- partition key: `template_id`
- sort key: `version_id`

The upload flow creates the baseline fields:

- `template_id`
- `version_id`
- `template_name`
- `file_name`
- `content_type`
- `expected_size_bytes`
- `s3_bucket`
- `s3_key`
- `status`
- `created_by`
- `created_at`
- `updated_at`

The validation runner now also writes validation-related metadata on the same item:

- `validation_started_at`
- `validation_completed_at`
- `validation_status`
- `validation_error_message`
- `validation_task_id`

Current state handling rules implemented by the runner are:

- only `UPLOADED` can move to `VALIDATING`
- only `VALIDATING` can move to `VALIDATED`
- only `VALIDATING` can move to `VALIDATION_FAILED`

`status` remains the main lifecycle field used by the API and by the runner. `validation_status` is an auxiliary execution field written by the validation task.

## Validation Runner Behavior

The validation runner is currently implemented around `scripts/validate_upload.sh`.

Current execution sequence:

1. derive `template_id` and `version_id` from the S3 key
2. mark the item as `VALIDATING`
3. download the ZIP from S3
4. extract the archive into a temporary workspace
5. resolve the Terraform root
6. execute the shared validation logic
7. mark the item as `VALIDATED` on success
8. mark the item as `VALIDATION_FAILED` on error

The first implemented Terraform checks are:

- `terraform fmt -check`
- `terraform init -backend=false`
- `terraform validate`

## Offline Provider Constraint

The runner currently executes in private subnets with no NAT, so `terraform init -backend=false` must succeed without public Internet access.

Because of that, Terraform providers used during validation must be embedded in the runner image through a controlled local mirror strategy.

The first approved offline provider baseline is:

- `registry.terraform.io/hashicorp/aws`
- version `5.100.0`

Current support rule:

- packages using `hashicorp/aws` `5.100.0` are inside the supported validation scope
- packages requiring another provider family or another provider version are outside the supported scope until the embedded mirror is expanded intentionally through a runner image release

## Current Implementation Status

The following points are implemented in the current repository state:

- the dedicated `validation-foundation` stack owns the EventBridge rule and ECS target for validation
- the ECS validation runner uses a dedicated `validate_upload.sh` entrypoint
- the raw upload bucket explicitly enables `S3 -> EventBridge` delivery in `dev`
- the trigger path is confirmed end to end in `dev`: raw upload -> EventBridge -> ECS RunTask
- the validation task uses environment-specific image tags so `dev` uses `inca-terraform-runner:dev` and `main` uses `inca-terraform-runner:main`
- the runner image embeds the approved Terraform provider baseline so validation can run offline in private subnets
- CloudWatch logs confirm a successful end-to-end validation run in `dev` for a supported AWS-only package
- DynamoDB state transitions are confirmed on the real path `PENDING -> UPLOADED -> VALIDATING -> VALIDATED`
- the CI/CD structure separates runner image publication, infrastructure delivery, and foundation administration

## Tests Currently In Place

The validation flow is currently protected by three categories of tests.

### 1. Shell And Script Syntax Checks

The runner-image pipeline validates shell syntax for the scripts used by the validation flow, including:

- `scripts/validate.sh`
- `scripts/validate_upload.sh`
- `scripts/test_offline_provider_mirror.sh`
- `scripts/test_upload_foundation_flow.sh`
- `scripts/test_validation_foundation_flow.sh`

This protects the pipeline from basic shell regressions before image publication.

### 2. Offline Provider Smoke Tests In The Runner-Image Pipeline

Two smoke tests validate the offline Terraform-provider behavior of the runner image:

- `offline_provider_supported_smoke`
- `offline_provider_unsupported_smoke`

What they verify:

- a supported Terraform fixture using `hashicorp/aws` `5.100.0` validates successfully with a local provider mirror
- an unsupported fixture using another provider fails as expected
- the failure path explicitly mentions the embedded provider mirror constraint

These tests validate the offline execution contract of the runner image itself.

### 3. Flow Smoke Tests In The Infrastructure Pipeline

The infrastructure pipeline currently contains manual smoke jobs for the deployed `dev` environment:

- `upload_foundation_smoke_dev`
- `validation_foundation_smoke_dev`

What `upload_foundation_smoke_dev` verifies:

- the upload API accepts a valid package through `prepare`
- the archive can be uploaded with the presigned URL
- the `complete` step succeeds
- the corresponding DynamoDB intent is readable from CI for follow-up checks

What `validation_foundation_smoke_dev` verifies:

- a package can go through `prepare -> upload -> complete`
- the validation flow is triggered after the upload is completed
- DynamoDB eventually reaches the expected final state, currently `VALIDATED`

This smoke job is the closest automated CI check to the real end-to-end validation path currently implemented in `dev`.

## What Is Not Fully Covered Yet

The current tests give a solid baseline, but they do not fully cover every operational scenario yet.

Open coverage gaps:

- duplicate S3 or EventBridge delivery is not yet formally tested
- the infrastructure smoke flow currently exercises the successful path, not a full `VALIDATION_FAILED` end-to-end scenario
- there is no automated assertion yet on detailed CloudWatch log content from CI
- there is no long-term approval workflow yet for adding new embedded provider families or versions

## Immediate Next Steps

The next implementation steps are:

1. improve runner failure messages so unsupported provider or runtime failures are easier to diagnose from DynamoDB and CloudWatch
2. harden duplicate-event handling and conditional state transitions
3. add an end-to-end failing-package smoke scenario that expects `VALIDATION_FAILED`
4. extend operational diagnostics around ECS task correlation and CloudWatch logs
5. define the controlled process for extending provider support over time
6. prepare the hand-off from validation to the future deployment flow

## Update Rule

This file must be updated whenever one of the following changes:

- validation architecture decisions
- target lifecycle and state transitions
- runtime network assumptions
- event contract
- runner responsibilities
- supported provider baseline
- testing strategy
