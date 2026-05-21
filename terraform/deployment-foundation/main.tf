provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Read Cognito pool ID and client ID from the cognito stack remote state so
# this stack stays in sync when the Cognito pool is destroyed and recreated.
data "terraform_remote_state" "cognito" {
  backend = "s3"
  config = {
    bucket = "inca-terraform-state-066122607629"
    key    = "platform/cognito/${var.environment}/terraform.tfstate"
    region = var.aws_region
  }
}

# Read subnet IDs and security group IDs from the validation-foundation remote
# state so the ECS task network config stays correct when the VPC is recreated.
data "terraform_remote_state" "validation" {
  backend = "s3"
  config = {
    bucket = "inca-terraform-state-066122607629"
    key    = "platform/validation-foundation/${var.environment}/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  deployment_container_name = "deployment-runner"

  upload_bucket_name = coalesce(
    var.upload_bucket_name,
    "inca-terraform-${var.environment}-${data.aws_caller_identity.current.account_id}"
  )

  upload_intents_table_name = coalesce(
    var.upload_intents_table_name,
    "inca-upload-intents-${var.environment}"
  )

  state_machine_name = coalesce(
    var.state_machine_name,
    "inca-deployment-${var.environment}"
  )

  deployment_runner_image_repository = coalesce(
    var.deployment_runner_image_repository,
    "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/inca-terraform-runner"
  )

  deployment_runner_image_uri = (
    var.deployment_runner_image_tag != null
    ? "${local.deployment_runner_image_repository}:${var.deployment_runner_image_tag}"
    : null
  )

  ecs_cluster_name = coalesce(
    var.ecs_cluster_name,
    "inca-deployment-cluster-${var.environment}"
  )

  ecs_task_family = coalesce(
    var.ecs_task_family,
    "inca-deployment-runner-${var.environment}"
  )

  cloudwatch_log_group_name = coalesce(
    var.cloudwatch_log_group_name,
    "/aws/ecs/inca-deployment-runner-${var.environment}"
  )

  api_gateway_name = coalesce(
    var.api_gateway_name,
    "inca-deployment-api-${var.environment}"
  )

  trigger_lambda_function_name = "trigger-deployment-${var.environment}"
  trigger_lambda_role_name     = "trigger-deployment-lambda-role-${var.environment}"
  trigger_lambda_policy_name   = "trigger-deployment-lambda-policy-${var.environment}"

  sfn_role_name      = "inca-deployment-sfn-role-${var.environment}"
  sfn_policy_name    = "inca-deployment-sfn-policy-${var.environment}"
  sfn_log_group_name = "/aws/states/inca-deployment-${var.environment}"

  ecs_execution_role_name = "inca-deployment-execution-role-${var.environment}"
  ecs_task_role_name      = "inca-deployment-task-role-${var.environment}"
  ecs_task_policy_name    = "inca-deployment-task-policy-${var.environment}"

  assign_public_ip_string = var.assign_public_ip ? "ENABLED" : "DISABLED"

  trigger_lambda_source_file = "${path.module}/../../lambdas/trigger-deployment/handler.py"
  trigger_lambda_output_zip  = "${path.module}/trigger-deployment.zip"

  common_tags = merge(var.tags, {
    environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "deployment" {
  name = local.ecs_cluster_name
  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# CloudWatch Log Groups
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "deployment_runner" {
  name              = local.cloudwatch_log_group_name
  retention_in_days = 365
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "sfn_deployment" {
  name              = local.sfn_log_group_name
  retention_in_days = 365
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "trigger_lambda" {
  name              = "/aws/lambda/${local.trigger_lambda_function_name}"
  retention_in_days = 365
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "deployment_api_access_logs" {
  name              = "/aws/apigatewayv2/${local.api_gateway_name}"
  retention_in_days = 365
  tags              = local.common_tags
}

# ---------------------------------------------------------------------------
# ECS IAM: Execution Role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    sid     = "AllowEcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = local.ecs_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# ECS IAM: Task Role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task" {
  name               = local.ecs_task_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "ecs_task" {
  statement {
    sid    = "AllowDynamoDbDeploymentStatus"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.upload_intents_table_name}"
    ]
  }

  statement {
    sid       = "AllowS3BlueprintDownload"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.upload_bucket_name}/blueprints/validated/*"]
  }

  statement {
    sid       = "AllowStsAssumeTargetSandboxRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/inca-learner-sandbox-*"]
  }
}

resource "aws_iam_policy" "ecs_task" {
  name   = local.ecs_task_policy_name
  policy = data.aws_iam_policy_document.ecs_task.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task.arn
}

# ---------------------------------------------------------------------------
# ECS Task Definition
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "deployment_runner" {
  family                   = local.ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = local.deployment_container_name
      image     = local.deployment_runner_image_uri
      essential = true
      command   = ["-lc", "/app/scripts/deploy.sh"]
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "UPLOAD_INTENTS_TABLE_NAME", value = local.upload_intents_table_name },
        { name = "DEPLOYMENT_S3_BUCKET", value = local.upload_bucket_name },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.cloudwatch_log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "deployment-runner"
        }
      }
    }
  ])

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Step Functions IAM Role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    sid     = "AllowStatesAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.state_machine_name}"
      ]
    }
  }
}

resource "aws_iam_role" "sfn_deployment" {
  name               = local.sfn_role_name
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "sfn_deployment" {
  statement {
    sid     = "AllowEcsRunTask"
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    resources = [
      replace(aws_ecs_task_definition.deployment_runner.arn, "/:[0-9]+$/", ":*")
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.deployment.arn]
    }
  }

  statement {
    sid     = "AllowEcsTaskManagement"
    effect  = "Allow"
    actions = ["ecs:StopTask", "ecs:DescribeTasks"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${local.ecs_cluster_name}/*"
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.deployment.arn]
    }
  }

  statement {
    sid     = "AllowIamPassRoleToEcs"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution.arn,
      aws_iam_role.ecs_task.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowEventBridgeForEcsSync"
    effect = "Allow"
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsForSfn"
    effect = "Allow"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "AllowCloudWatchLogEventsForSfn"
    effect    = "Allow"
    actions   = ["logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.sfn_deployment.arn}:*"]
  }
}

resource "aws_iam_policy" "sfn_deployment" {
  name   = local.sfn_policy_name
  policy = data.aws_iam_policy_document.sfn_deployment.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "sfn_deployment" {
  role       = aws_iam_role.sfn_deployment.name
  policy_arn = aws_iam_policy.sfn_deployment.arn
}

# ---------------------------------------------------------------------------
# Step Functions State Machine
# ---------------------------------------------------------------------------

resource "aws_sfn_state_machine" "deployment" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.sfn_deployment.arn

  definition = jsonencode({
    Comment = "Runs the deployment ECS Fargate task for a single learner environment."
    StartAt = "RunDeploymentTask"
    States = {
      RunDeploymentTask = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = aws_ecs_cluster.deployment.arn
          TaskDefinition = aws_ecs_task_definition.deployment_runner.arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = try(data.terraform_remote_state.validation.outputs.validation_private_subnet_ids, [])
              SecurityGroups = try(data.terraform_remote_state.validation.outputs.validation_task_security_group_ids, [])
              AssignPublicIp = local.assign_public_ip_string
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name = local.deployment_container_name
                Environment = [
                  { "Name" = "TEMPLATE_ID", "Value.$" = "$.template_id" },
                  { "Name" = "VERSION_ID", "Value.$" = "$.version_id" },
                  { "Name" = "TARGET_ACCOUNT_ID", "Value.$" = "$.target_account_id" },
                  { "Name" = "TARGET_ROLE_NAME", "Value.$" = "$.target_role_name" },
                  { "Name" = "DEPLOYMENT_S3_KEY", "Value.$" = "$.s3_key" },
                ]
              }
            ]
          }
        }
        End = true
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_deployment.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Lambda: trigger-deployment
# ---------------------------------------------------------------------------

data "archive_file" "trigger_deployment_lambda" {
  type        = "zip"
  source_file = local.trigger_lambda_source_file
  output_path = local.trigger_lambda_output_zip
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trigger_lambda" {
  name               = local.trigger_lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "trigger_lambda" {
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }

  statement {
    sid    = "AllowDynamoDbBlueprintAccess"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.upload_intents_table_name}"
    ]
  }

  statement {
    sid       = "AllowSfnStartExecution"
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.deployment.arn]
  }
}

resource "aws_iam_policy" "trigger_lambda" {
  name   = local.trigger_lambda_policy_name
  policy = data.aws_iam_policy_document.trigger_lambda.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "trigger_lambda" {
  role       = aws_iam_role.trigger_lambda.name
  policy_arn = aws_iam_policy.trigger_lambda.arn
}

resource "aws_lambda_function" "trigger_deployment" {
  function_name    = local.trigger_lambda_function_name
  role             = aws_iam_role.trigger_lambda.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.trigger_deployment_lambda.output_path
  source_code_hash = data.archive_file.trigger_deployment_lambda.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      UPLOAD_INTENTS_TABLE_NAME    = local.upload_intents_table_name
      DEPLOYMENT_STATE_MACHINE_ARN = aws_sfn_state_machine.deployment.arn
      COGNITO_USER_POOL_ID         = try(data.terraform_remote_state.cognito.outputs.user_pool_id, "")
      COGNITO_CLIENT_ID            = try(data.terraform_remote_state.cognito.outputs.user_pool_client_id, "")
    }
  }

  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.trigger_lambda.name
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# API Gateway HTTP: POST /deployments
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "deployment" {
  name          = local.api_gateway_name
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_integration" "trigger_deployment" {
  api_id                 = aws_apigatewayv2_api.deployment.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.trigger_deployment.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "trigger_deployment" {
  api_id    = aws_apigatewayv2_api.deployment.id
  route_key = "POST /deployments"
  target    = "integrations/${aws_apigatewayv2_integration.trigger_deployment.id}"
}

resource "aws_apigatewayv2_stage" "deployment" {
  api_id      = aws_apigatewayv2_api.deployment.id
  name        = var.http_api_stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.deployment_api_access_logs.arn
    format = jsonencode({
      requestId            = "$context.requestId"
      ip                   = "$context.identity.sourceIp"
      requestTime          = "$context.requestTime"
      httpMethod           = "$context.httpMethod"
      routeKey             = "$context.routeKey"
      status               = "$context.status"
      protocol             = "$context.protocol"
      responseLength       = "$context.responseLength"
      responseLatencyMs    = "$context.responseLatency"
      integrationLatencyMs = "$context.integrationLatency"
      integrationStatus    = "$context.integrationStatus"
      errorMessage         = "$context.error.message"
    })
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowHttpApiInvokeTriggerDeployment"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger_deployment.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.deployment.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# SNS: Deployment Alerts
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "deployment_alerts" {
  name = "inca-deployment-alerts-${var.environment}"
  tags = local.common_tags
}

# Allows CloudWatch Alarms to publish to the topic.
resource "aws_sns_topic_policy" "deployment_alerts" {
  arn = aws_sns_topic.deployment_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.deployment_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "deployment_alerts_email" {
  count = var.alert_email != null ? 1 : 0

  topic_arn = aws_sns_topic.deployment_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# CloudWatch: ECS Log Metric Filter + Alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "ecs_deployment_errors" {
  name           = "inca-deployment-runner-errors-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.deployment_runner.name
  pattern        = "?ERROR ?error ?FAILED ?failed"

  metric_transformation {
    name          = "DeploymentRunnerErrors"
    namespace     = "INCA/Deployment"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_deployment_errors" {
  alarm_name          = "inca-deployment-ecs-errors-${var.environment}"
  alarm_description   = "Deployment ECS runner task errors detected in logs."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.ecs_deployment_errors.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.ecs_deployment_errors.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.deployment_alerts.arn]
  ok_actions          = [aws_sns_topic.deployment_alerts.arn]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "inca-deployment-lambda-errors-${var.environment}"
  alarm_description   = "Deployment trigger Lambda invocation errors."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.deployment_alerts.arn]
  ok_actions          = [aws_sns_topic.deployment_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.trigger_deployment.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sfn_executions_failed" {
  alarm_name          = "inca-deployment-sfn-failed-${var.environment}"
  alarm_description   = "Deployment Step Functions execution failures."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.deployment_alerts.arn]
  ok_actions          = [aws_sns_topic.deployment_alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.deployment.arn
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sfn_executions_throttled" {
  alarm_name          = "inca-deployment-sfn-throttled-${var.environment}"
  alarm_description   = "Deployment Step Functions execution throttling."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionThrottled"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.deployment_alerts.arn]
  ok_actions          = [aws_sns_topic.deployment_alerts.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.deployment.arn
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "deployment_api_5xx_errors" {
  alarm_name          = "inca-deployment-api-5xx-${var.environment}"
  alarm_description   = "Deployment API Gateway 5xx errors — Lambda integration failures."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.deployment.id }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.deployment_alerts.arn]
  ok_actions          = [aws_sns_topic.deployment_alerts.arn]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "deployment_api_4xx_errors" {
  alarm_name          = "inca-deployment-api-4xx-${var.environment}"
  alarm_description   = "Deployment API Gateway 4xx errors — sustained rate suggests auth issues or bad clients."
  namespace           = "AWS/ApiGateway"
  metric_name         = "4xx"
  dimensions          = { ApiId = aws_apigatewayv2_api.deployment.id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.deployment_alerts.arn]
  ok_actions          = [aws_sns_topic.deployment_alerts.arn]
  tags                = local.common_tags
}
