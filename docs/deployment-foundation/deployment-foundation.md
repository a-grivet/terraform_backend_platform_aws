# Deployment Foundation

## Overview

The `deployment-foundation` stack is the runtime engine that executes a Terraform blueprint inside a learner's sandbox AWS account. It exposes a single HTTP API that a learner calls with a JWT token to trigger a deployment; the request travels through Lambda, Step Functions, and an ECS Fargate task that actually runs `deploy.sh` against the target account.

```
Learner
   │  POST /deployments  { template_id, version_id }
   │  Authorization: Bearer <cognito-id-token>
   ▼
CloudFront (WAF edge)
   ▼
API Gateway HTTP  inca-deployment-api-{env}  (eu-west-3)
   ▼
Lambda  trigger-deployment-{env}
   ├─ validate JWT (Cognito JWKS)
   ├─ DynamoDB GetItem → check status = READY
   ├─ DynamoDB UpdateItem → READY → DEPLOYING  (conditional, atomic)
   └─ Step Functions StartExecution
        └─ inca-deployment-{env}  (RunDeploymentTask state)
             └─ ECS Fargate task  inca-deployment-runner-{env}
                  ├─ S3 GetObject  blueprints/validated/<s3_key>
                  ├─ DynamoDB UpdateItem  (deployment result)
                  └─ STS AssumeRole → inca-learner-sandbox-*
                       └─ Terraform apply in sandbox account
```

---

## 1. Components

| Component | Name pattern | Description |
|-----------|-------------|-------------|
| API Gateway HTTP | `inca-deployment-api-{env}` | Single route `POST /deployments`, stage `api`, auto-deploy |
| Lambda | `trigger-deployment-{env}` | JWT validation + DynamoDB state transition + SFN trigger |
| Step Functions | `inca-deployment-{env}` | Orchestrates a single ECS Fargate task synchronously |
| ECS Cluster | `inca-deployment-cluster-{env}` | Fargate cluster, no persistent compute |
| ECS Task Definition | `inca-deployment-runner-{env}` | Runs `deploy.sh` from the Terraform runner image |
| S3 Bucket | `inca-terraform-{env}-{account_id}` | Source for validated blueprints (read-only by task) |
| DynamoDB Table | `inca-upload-intents-{env}` | Stores blueprint metadata and deployment status |
| SNS Topic | `inca-deployment-alerts-{env}` | Receives CloudWatch alarm notifications |

> The S3 bucket and DynamoDB table are created by `upload-foundation`. The deployment stack reads their names via variables (defaulting to the same naming convention) and is granted its own IAM access to them.

---

## 2. API

### Route

```
POST  https://<cloudfront-domain>/api/deployments
```

The CloudFront domain is the public entry point. The underlying API Gateway endpoint is `https://{api_id}.execute-api.eu-west-3.amazonaws.com/api/deployments`.

### Request

```http
POST /deployments HTTP/1.1
Authorization: Bearer <cognito-id-token>
Content-Type: application/json

{
  "template_id": "aws-lab-vpc",
  "version_id": "v1.2.0"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `template_id` | string | yes | Blueprint identifier |
| `version_id` | string | yes | Blueprint version |
| `Authorization` | header | yes | Cognito ID token (not access token) |

### Responses

| Status | Meaning | Body |
|--------|---------|------|
| `202 Accepted` | Deployment successfully started | `{ message, template_id, version_id, execution_arn }` |
| `400 Bad Request` | Missing/invalid body fields | `{ error: "<reason>" }` |
| `401 Unauthorized` | Missing, expired, or invalid JWT | `{ error: "<reason>" }` |
| `409 Conflict` | Blueprint is not in READY state, or concurrent deployment in progress | `{ error: "<reason>" }` |
| `500 Internal Server Error` | Unexpected Lambda/AWS error | `{ error: "Internal server error" }` |

#### 202 response body

```json
{
  "message": "Deployment started",
  "template_id": "aws-lab-vpc",
  "version_id": "v1.2.0",
  "execution_arn": "arn:aws:states:eu-west-3:066122607629:execution:inca-deployment-dev:abc123"
}
```

---

## 3. Lambda: `trigger-deployment-{env}`

### Configuration

| Parameter | Value |
|-----------|-------|
| Runtime | Python 3.12 |
| Handler | `handler.handler` |
| Timeout | 30 seconds |
| Memory | 256 MB |
| Log format | JSON, application level INFO, system level WARN |
| Log group | `/aws/lambda/trigger-deployment-{env}` (365-day retention) |

### Environment variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `UPLOAD_INTENTS_TABLE_NAME` | Terraform local | DynamoDB table name for blueprint status |
| `DEPLOYMENT_STATE_MACHINE_ARN` | `aws_sfn_state_machine.deployment.arn` | Step Functions ARN to start |
| `COGNITO_USER_POOL_ID` | `var.cognito_user_pool_id` | For JWKS URL construction |
| `COGNITO_CLIENT_ID` | `var.cognito_client_id` | Expected `aud` claim in the ID token |

### Execution flow

```
1. Parse request
   ├─ Extract Bearer token from Authorization header
   └─ Deserialize JSON body → { template_id, version_id }

2. Validate JWT
   ├─ Base64-decode payload (no signature verification, see note below)
   ├─ Check token_use == "id"
   ├─ Check aud == COGNITO_CLIENT_ID
   └─ Check exp > now()

3. Extract learner context from claims
   ├─ custom:aws_account_id   (required)
   ├─ custom:role_name        (required)
   ├─ custom:cohort_id        (optional, defaults to "")
   └─ sub                     (Cognito user identifier)

4. DynamoDB GetItem  (template_id + version_id as composite key)
   └─ Raise 400 if item not found
   └─ Raise 409 if status != READY

5. DynamoDB UpdateItem  (conditional write)
   ConditionExpression: #status = :expected (READY)
   UpdateExpression:
     SET #status = DEPLOYING,
         user_status = IN_PROGRESS,
         updated_at = <now>,
         deployment_started_at = <now>,
         deployment_account_id = <learner.aws_account_id>,
         deployment_role_name = <learner.role_name>,
         deployment_cohort_id = <learner.cohort_id>
     REMOVE deployment_error_message, failure_stage
   └─ ConditionalCheckFailedException → 409 (concurrent deployment guard)

6. Step Functions StartExecution
   Payload: {
     template_id, version_id, s3_key,
     target_account_id, target_role_name,
     cohort_id, user_sub
   }
   └─ Returns execution_arn

7. Return 202 { message, template_id, version_id, execution_arn }
```

> **JWT signature verification note**: The current implementation decodes the JWT payload without verifying the RS256 signature against Cognito's JWKS public keys. The token is fetched from the JWKS endpoint (cached 1 hour in Lambda memory) but only the claims are inspected. For production hardening, add `PyJWT` + `cryptography` and verify the full signature.

### JWKS cache

The Lambda maintains an in-memory cache for the Cognito JWKS endpoint:

```
URL: https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json
TTL: 3600 seconds (1 hour)
Scope: Lambda execution environment (warm instance only)
```

The cache avoids an HTTPS round-trip on every invocation. It is invalidated after 1 hour or whenever a cold start occurs.

---

## 4. DynamoDB: status transitions

The `inca-upload-intents-{env}` table is shared between the upload, validation, and deployment stacks. Each stack is responsible for its own status transitions.

| Trigger | Status before | Status after | Actor |
|---------|--------------|--------------|-------|
| Upload prepared | — | `PENDING` | `prepare-upload` Lambda |
| Validation started | `PENDING` | `VALIDATING` | Validation ECS task |
| Validation passed | `VALIDATING` | `READY` | Validation ECS task |
| Deployment triggered | `READY` | `DEPLOYING` | `trigger-deployment` Lambda |
| Deployment succeeded | `DEPLOYING` | `DEPLOYED` | Deployment ECS task |
| Deployment failed | `DEPLOYING` | `FAILED` | Deployment ECS task |

The `trigger-deployment` Lambda writes `DEPLOYING` using a `ConditionExpression` that requires the current status to be `READY`. This is an atomic check-and-set: if two requests arrive simultaneously for the same blueprint, only one will succeed; the second will receive a `ConditionalCheckFailedException` → `409 Conflict`.

---

## 5. Step Functions

### State machine

| Parameter | Value |
|-----------|-------|
| Name | `inca-deployment-{env}` |
| Single state | `RunDeploymentTask` |
| Resource | `arn:aws:states:::ecs:runTask.sync` |
| Launch type | `FARGATE` |
| Logging | ALL level, log group `/aws/states/inca-deployment-{env}`, 365-day retention |

### `ecs:runTask.sync` semantics

The `.sync` suffix means Step Functions waits for the ECS task to complete before transitioning. It uses EventBridge under the hood to receive the task-stopped event without polling. The state machine execution stays open (and billable) for the entire duration of the task.

### Container overrides

The task definition sets static environment variables. Per-deployment values are injected at runtime via `ContainerOverrides`:

| Override variable | Source in SFN input |
|------------------|---------------------|
| `TEMPLATE_ID` | `$.template_id` |
| `VERSION_ID` | `$.version_id` |
| `TARGET_ACCOUNT_ID` | `$.target_account_id` |
| `TARGET_ROLE_NAME` | `$.target_role_name` |
| `DEPLOYMENT_S3_KEY` | `$.s3_key` |

---

## 6. ECS Task: `inca-deployment-runner-{env}`

### Task definition

| Parameter | Value |
|-----------|-------|
| Family | `inca-deployment-runner-{env}` |
| Requires compatibilities | `FARGATE` |
| Network mode | `awsvpc` |
| CPU | 1024 units (1 vCPU) — configurable via `task_cpu` |
| Memory | 2048 MiB — configurable via `task_memory` |
| Command | `/app/scripts/deploy.sh` |
| Log group | `/aws/ecs/inca-deployment-runner-{env}` (365-day retention) |

### Container image

The image is built from the project's `Dockerfile` and pushed to ECR (`inca-terraform-runner`). The tag is an immutable 40-character Git commit SHA (`deployment_runner_image_tag`), validated by a Terraform variable rule. On `dev`, the mutable `dev` tag is used; on `main`, the mutable `main` tag.

### Static environment variables (from task definition)

| Variable | Source |
|----------|--------|
| `AWS_REGION` | `var.aws_region` |
| `UPLOAD_INTENTS_TABLE_NAME` | Terraform local |
| `DEPLOYMENT_S3_BUCKET` | Terraform local |

### Dynamic environment variables (from SFN container overrides)

| Variable | Value |
|----------|-------|
| `TEMPLATE_ID` | Blueprint template identifier |
| `VERSION_ID` | Blueprint version identifier |
| `TARGET_ACCOUNT_ID` | Learner's sandbox account ID |
| `TARGET_ROLE_NAME` | IAM role to assume in the sandbox |
| `DEPLOYMENT_S3_KEY` | S3 key for the validated blueprint archive |

### Networking

The task runs in `awsvpc` mode. Subnets and security groups are provided via `var.subnet_ids` and `var.security_group_ids`. `assign_public_ip` defaults to `false`; tasks in private subnets use a NAT Gateway or VPC endpoints to reach AWS services.

---

## 7. IAM roles

### ECS Execution Role: `inca-deployment-execution-role-{env}`

Managed policy: `AmazonECSTaskExecutionRolePolicy` (pull image from ECR, write CloudWatch logs).

### ECS Task Role: `inca-deployment-task-role-{env}`

| Permission | Resource | Purpose |
|------------|---------|---------|
| `dynamodb:GetItem`, `dynamodb:UpdateItem` | `inca-upload-intents-{env}` | Read blueprint metadata, write deployment result |
| `s3:GetObject` | `inca-terraform-{env}-{account_id}/blueprints/validated/*` | Download validated blueprint archive |
| `sts:AssumeRole` | `arn:aws:iam::*:role/inca-learner-sandbox-*` | Cross-account assume role into any sandbox |

### Step Functions Role: `inca-deployment-sfn-role-{env}`

| Permission | Resource | Purpose |
|------------|---------|---------|
| `ecs:RunTask` | `inca-deployment-runner-{env}:*` (any revision) | Launch the deployment task |
| `ecs:StopTask`, `ecs:DescribeTasks` | Tasks in `inca-deployment-cluster-{env}` | Task lifecycle management |
| `iam:PassRole` | Execution role + task role | Grant ECS the two task roles |
| `events:PutTargets`, `events:PutRule`, `events:DescribeRule` | `StepFunctionsGetEventsForECSTaskRule` | EventBridge rule for `.sync` integration |
| `logs:*` (delivery) | `*` (CloudWatch API constraint) | Write SFN execution logs |
| `logs:PutLogEvents` | SFN log group | Log execution events |

### Lambda Role: `trigger-deployment-lambda-role-{env}`

| Permission | Resource | Purpose |
|------------|---------|---------|
| `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` | Account-level | Write invocation logs |
| `dynamodb:GetItem`, `dynamodb:UpdateItem` | `inca-upload-intents-{env}` | Read status + conditional update to DEPLOYING |
| `states:StartExecution` | `inca-deployment-{env}` state machine | Trigger deployment |

---

## 8. CloudWatch: log groups and alarms

### Log groups

| Log group | Component | Retention |
|-----------|-----------|-----------|
| `/aws/ecs/inca-deployment-runner-{env}` | ECS task | 365 days |
| `/aws/states/inca-deployment-{env}` | Step Functions | 365 days |
| `/aws/lambda/trigger-deployment-{env}` | Lambda | 365 days |
| `/aws/apigatewayv2/inca-deployment-api-{env}` | API Gateway access logs | 365 days |

### Alarms

| Alarm | Metric | Threshold | Period | Evaluation | Trigger |
|-------|--------|-----------|--------|------------|---------|
| `inca-deployment-ecs-errors-{env}` | Custom `DeploymentRunnerErrors` (log filter: ERROR/FAILED) | > 0 | 300s | 1 | ECS task errors in logs |
| `inca-deployment-lambda-errors-{env}` | `AWS/Lambda Errors` | > 0 | 300s | 1 | Lambda invocation errors |
| `inca-deployment-sfn-failed-{env}` | `AWS/States ExecutionsFailed` | > 0 | 300s | 1 | SFN execution failures |
| `inca-deployment-sfn-throttled-{env}` | `AWS/States ExecutionThrottled` | > 0 | 300s | 1 | SFN throttling |
| `inca-deployment-api-5xx-{env}` | `AWS/ApiGateway 5xx` | ≥ 1 | 60s | 1 | Lambda integration failures |
| `inca-deployment-api-4xx-{env}` | `AWS/ApiGateway 4xx` | ≥ 10 | 300s | 3 | Sustained auth/validation errors |

All alarms publish to `inca-deployment-alerts-{env}` SNS topic. `alert_email` in `dev.tfvars` controls whether an email subscription is created.

### API Gateway access log fields

Each request writes a JSON record to `/aws/apigatewayv2/inca-deployment-api-{env}`:

```json
{
  "requestId": "...",
  "ip": "...",
  "requestTime": "...",
  "httpMethod": "POST",
  "routeKey": "POST /deployments",
  "status": 202,
  "protocol": "HTTP/1.1",
  "responseLength": 156,
  "responseLatencyMs": 1234,
  "integrationLatencyMs": 1200,
  "integrationStatus": 202,
  "errorMessage": null
}
```

---

## 9. Terraform variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `eu-west-3` | Region for all resources |
| `environment` | `dev` | Used in resource names |
| `cognito_user_pool_id` | required | Cognito User Pool ID |
| `cognito_client_id` | required | Cognito app client ID |
| `subnet_ids` | required | Subnets for ECS tasks |
| `security_group_ids` | required | Security groups for ECS tasks |
| `deployment_runner_image_tag` | `null` | Git commit SHA for runner image |
| `task_cpu` | `1024` | vCPU units for ECS task |
| `task_memory` | `2048` | Memory in MiB for ECS task |
| `assign_public_ip` | `false` | Whether ECS tasks get a public IP |
| `alert_email` | `null` | Email for SNS alarm notifications |
| `http_api_stage_name` | `api` | API Gateway stage name (must be non-`$default` for WAF) |
| `upload_bucket_name` | computed | Override for S3 bucket name |
| `upload_intents_table_name` | computed | Override for DynamoDB table name |

---

## 10. Naming conventions

| Resource | Pattern |
|---------|---------|
| ECS Cluster | `inca-deployment-cluster-{env}` |
| ECS Task Family | `inca-deployment-runner-{env}` |
| Step Functions | `inca-deployment-{env}` |
| API Gateway | `inca-deployment-api-{env}` |
| Lambda | `trigger-deployment-{env}` |
| Lambda IAM Role | `trigger-deployment-lambda-role-{env}` |
| Lambda IAM Policy | `trigger-deployment-lambda-policy-{env}` |
| ECS Execution Role | `inca-deployment-execution-role-{env}` |
| ECS Task Role | `inca-deployment-task-role-{env}` |
| ECS Task Policy | `inca-deployment-task-policy-{env}` |
| SFN IAM Role | `inca-deployment-sfn-role-{env}` |
| SFN IAM Policy | `inca-deployment-sfn-policy-{env}` |
| SNS Topic | `inca-deployment-alerts-{env}` |
| CW Log group (ECS) | `/aws/ecs/inca-deployment-runner-{env}` |
| CW Log group (SFN) | `/aws/states/inca-deployment-{env}` |
| CW Log group (Lambda) | `/aws/lambda/trigger-deployment-{env}` |
| CW Log group (API) | `/aws/apigatewayv2/inca-deployment-api-{env}` |

---

## 11. Deployment order and dependencies

This stack depends on outputs from other stacks:

```
waf-foundation    ──────────────────────────────────┐
                                                    │ web_acl_arn (via cloudfront-foundation)
upload-foundation ─── S3 bucket + DynamoDB table ──┤
                       (naming convention shared)   │
cognito           ─── user_pool_id + client_id ─────┤
                                                    ▼
                                    deployment-foundation
                                         │
                                         ▼
                                  cloudfront-foundation
                                  (reads deployment_api_id via remote state)
```

Remote state key: `platform/deployment-foundation/{env}/terraform.tfstate`  
Bucket: `inca-terraform-state-066122607629` (eu-west-3)
