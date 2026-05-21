provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  validation_container_name = "validation-runner"

  upload_bucket_name = coalesce(
    var.upload_bucket_name,
    "inca-terraform-${var.environment}-${data.aws_caller_identity.current.account_id}"
  )

  upload_intents_table_name = coalesce(
    var.upload_intents_table_name,
    "inca-upload-intents-${var.environment}"
  )

  validation_runner_image_repository = coalesce(
    var.validation_runner_image_repository,
    "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/inca-terraform-runner"
  )

  validation_runner_image_uri = var.validation_runner_image_tag != null ? "${local.validation_runner_image_repository}:${var.validation_runner_image_tag}" : null

  ecs_cluster_name = coalesce(
    var.ecs_cluster_name,
    "inca-validation-cluster-${var.environment}"
  )

  ecs_task_family = coalesce(
    var.ecs_task_family,
    "inca-validation-runner-${var.environment}"
  )

  event_rule_name = coalesce(
    var.event_rule_name,
    "inca-validation-upload-trigger-${var.environment}"
  )

  cloudwatch_log_group_name = coalesce(
    var.cloudwatch_log_group_name,
    "/aws/ecs/inca-validation-runner-${var.environment}"
  )

  vpc_flow_logs_log_group_name = coalesce(
    var.vpc_flow_logs_log_group_name,
    "/aws/vpc-flow-logs/inca-validation-${var.environment}"
  )

  ecs_execution_role_name      = "inca-validation-execution-role-${var.environment}"
  ecs_task_role_name           = "inca-validation-task-role-${var.environment}"
  eventbridge_target_role_name = "inca-validation-eventbridge-invoke-role-${var.environment}"
  endpoint_security_group_name = "inca-validation-vpc-endpoints-${var.environment}"
  flow_logs_role_name          = "inca-validation-vpc-flow-logs-role-${var.environment}"
  task_security_group_name     = "inca-validation-tasks-${var.environment}"
  private_route_table_name     = "inca-validation-private-${var.environment}"
  vpc_name                     = "inca-validation-vpc-${var.environment}"

  vpc_flow_logs_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${flow-direction} $${traffic-path}"

  common_tags = merge(
    var.tags,
    {
      environment = var.environment
      component   = "validation-foundation"
    }
  )

  private_service_endpoint_common_tags = merge(
    local.common_tags,
    {
      service = "vpc-endpoint"
      purpose = "private-aws-service-connectivity"
    }
  )

  private_service_endpoint_eni_common_tags = merge(
    local.common_tags,
    {
      service = "vpc-endpoint-eni"
      purpose = "private-aws-service-connectivity"
    }
  )

  validation_upload_event_pattern = jsonencode(
    {
      source      = ["aws.s3"]
      detail-type = ["Object Created"]
      detail = {
        bucket = {
          name = [local.upload_bucket_name]
        }
        object = {
          key = [
            {
              prefix = var.raw_upload_key_prefix
            }
          ]
        }
      }
    }
  )

  validation_runner_container_definitions = jsonencode(
    [
      {
        name      = local.validation_container_name
        image     = local.validation_runner_image_uri
        essential = true
        command = [
          "-lc",
          "/app/scripts/validate_upload.sh"
        ]
        environment = [
          {
            name  = "UPLOAD_INTENTS_TABLE_NAME"
            value = local.upload_intents_table_name
          },
          {
            name  = "AWS_REGION"
            value = var.aws_region
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = local.cloudwatch_log_group_name
            awslogs-region        = var.aws_region
            awslogs-stream-prefix = "validation-runner"
          }
        }
      }
    ]
  )

  network_availability_zones = length(var.validation_availability_zones) > 0 ? var.validation_availability_zones : slice(
    data.aws_availability_zones.available.names,
    0,
    length(var.validation_private_subnet_cidrs)
  )

  effective_vpc_id = var.create_validation_network ? aws_vpc.validation[0].id : var.vpc_id

  effective_subnet_ids = var.create_validation_network ? aws_subnet.validation_private[*].id : var.subnet_ids

  effective_task_security_group_ids = var.create_validation_network ? [aws_security_group.validation_tasks[0].id] : var.security_group_ids

  effective_private_route_table_ids = var.create_validation_network ? [aws_route_table.validation_private[0].id] : var.private_route_table_ids

  interface_endpoint_subnet_ids = var.create_validation_network ? aws_subnet.validation_private[*].id : (
    length(var.interface_endpoint_subnet_ids) > 0 ? var.interface_endpoint_subnet_ids : var.subnet_ids
  )

  manage_vpc_flow_logs = var.create_validation_network || var.enable_vpc_flow_logs

  validation_task_definition_family_arn = var.enable_validation_runtime ? replace(
    aws_ecs_task_definition.validation_runner[0].arn,
    "/:[0-9]+$/",
    ":*"
  ) : null
}

resource "aws_cloudwatch_event_rule" "validation_upload_trigger" {
  name           = local.event_rule_name
  description    = "Triggers the validation flow for pending uploaded Terraform ZIP packages."
  event_bus_name = var.event_bus_name
  event_pattern  = local.validation_upload_event_pattern
  state          = var.enable_validation_trigger ? "ENABLED" : "DISABLED"
  tags           = local.common_tags
}

resource "aws_cloudwatch_log_group" "validation_runner" {
  count = var.enable_validation_runtime ? 1 : 0

  name              = local.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = local.manage_vpc_flow_logs ? 1 : 0

  name              = local.vpc_flow_logs_log_group_name
  retention_in_days = var.vpc_flow_logs_retention_days

  tags = merge(
    local.common_tags,
    {
      Name    = local.vpc_flow_logs_log_group_name
      service = "vpc-flow-logs"
      purpose = "network-observability"
    }
  )
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = local.manage_vpc_flow_logs ? 1 : 0

  name = local.flow_logs_role_name

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = "vpc-flow-logs.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )

  tags = merge(
    local.common_tags,
    {
      Name    = local.flow_logs_role_name
      service = "vpc-flow-logs"
      purpose = "network-observability"
    }
  )
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = local.manage_vpc_flow_logs ? 1 : 0

  name = "publish-vpc-flow-logs"
  role = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents"
          ]
          Resource = [
            aws_cloudwatch_log_group.vpc_flow_logs[0].arn,
            "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
          ]
        }
      ]
    }
  )
}

# If this foundation is later integrated into an existing platform network,
# these resources should be adapted to that existing VPC topology or removed.
resource "aws_vpc" "validation" {
  count = var.create_validation_network ? 1 : 0

  cidr_block           = var.validation_vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    {
      Name = local.vpc_name
    }
  )
}

resource "aws_default_security_group" "validation" {
  count = var.create_validation_network ? 1 : 0

  vpc_id = aws_vpc.validation[0].id

  ingress = []
  egress  = []

  tags = merge(
    local.common_tags,
    {
      Name = "${local.vpc_name}-default-sg"
    }
  )
}

# If this foundation is later integrated into an existing platform network,
# these resources should be adapted to that existing VPC topology or removed.
resource "aws_subnet" "validation_private" {
  count = var.create_validation_network ? length(var.validation_private_subnet_cidrs) : 0

  vpc_id                  = aws_vpc.validation[0].id
  cidr_block              = var.validation_private_subnet_cidrs[count.index]
  availability_zone       = local.network_availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    local.common_tags,
    {
      Name = "inca-validation-private-${var.environment}-${count.index + 1}"
    }
  )
}

# If this foundation is later integrated into an existing platform network,
# these resources should be adapted to that existing VPC topology or removed.
resource "aws_route_table" "validation_private" {
  count = var.create_validation_network ? 1 : 0

  vpc_id = aws_vpc.validation[0].id

  tags = merge(
    local.common_tags,
    {
      Name = local.private_route_table_name
    }
  )
}

# If this foundation is later integrated into an existing platform network,
# these resources should be adapted to that existing VPC topology or removed.
resource "aws_route_table_association" "validation_private" {
  count = var.create_validation_network ? length(aws_subnet.validation_private) : 0

  subnet_id      = aws_subnet.validation_private[count.index].id
  route_table_id = aws_route_table.validation_private[0].id
}

resource "aws_flow_log" "validation_vpc" {
  count = var.create_validation_network ? 1 : 0

  iam_role_arn    = aws_iam_role.vpc_flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  log_format      = local.vpc_flow_logs_format
  traffic_type    = var.vpc_flow_logs_traffic_type
  vpc_id          = aws_vpc.validation[0].id

  tags = merge(
    local.common_tags,
    {
      Name        = "inca-validation-vpc-flow-logs-${var.environment}"
      service     = "vpc-flow-logs"
      purpose     = "network-observability"
      traffic     = var.vpc_flow_logs_traffic_type
      destination = "cloudwatch-logs"
    }
  )
}

resource "aws_flow_log" "existing_vpc" {
  count = !var.create_validation_network && var.enable_vpc_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.vpc_flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  log_format      = local.vpc_flow_logs_format
  traffic_type    = var.vpc_flow_logs_traffic_type
  vpc_id          = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name        = "inca-validation-vpc-flow-logs-${var.environment}"
      service     = "vpc-flow-logs"
      purpose     = "network-observability"
      traffic     = var.vpc_flow_logs_traffic_type
      destination = "cloudwatch-logs"
    }
  )
}

# If this foundation is later integrated into an existing platform network,
# these resources should be adapted to that existing VPC topology or removed.
resource "aws_security_group" "validation_tasks" {
  count = var.create_validation_network ? 1 : 0

  name        = local.task_security_group_name
  description = "Security group attached to validation runner tasks."
  vpc_id      = aws_vpc.validation[0].id
  tags        = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "validation_tasks_all" {
  count = var.create_validation_network ? 1 : 0

  security_group_id = aws_security_group.validation_tasks[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow validation tasks to reach AWS service endpoints."
}

# If this foundation is later integrated into an existing platform network,
# these resources should be adapted to that existing VPC topology or removed.
resource "aws_security_group" "private_service_endpoints" {
  count = var.manage_private_service_endpoints ? 1 : 0

  name        = local.endpoint_security_group_name
  description = "Allows validation runner tasks to reach private interface endpoints over HTTPS."
  vpc_id      = local.effective_vpc_id
  tags        = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "private_service_endpoints_https" {
  count = var.manage_private_service_endpoints ? length(local.effective_task_security_group_ids) : 0

  security_group_id            = aws_security_group.private_service_endpoints[0].id
  referenced_security_group_id = local.effective_task_security_group_ids[count.index]
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Allow HTTPS from validation runner task security groups."
}

resource "aws_vpc_security_group_egress_rule" "private_service_endpoints_all" {
  count = var.manage_private_service_endpoints ? 1 : 0

  security_group_id = aws_security_group.private_service_endpoints[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow endpoint responses to leave the security group."
}

resource "aws_vpc_endpoint" "s3" {
  count = var.manage_private_service_endpoints ? 1 : 0

  vpc_id            = local.effective_vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.effective_private_route_table_ids

  tags = merge(
    local.private_service_endpoint_common_tags,
    {
      Name             = "inca-validation-s3-endpoint-${var.environment}"
      endpoint_service = "s3"
      endpoint_type    = "gateway"
    }
  )
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.manage_private_service_endpoints ? 1 : 0

  vpc_id            = local.effective_vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.effective_private_route_table_ids

  tags = merge(
    local.private_service_endpoint_common_tags,
    {
      Name             = "inca-validation-dynamodb-endpoint-${var.environment}"
      endpoint_service = "dynamodb"
      endpoint_type    = "gateway"
    }
  )
}

# ECR API covers the control-plane API used to resolve repository metadata,
# image manifests, and authorization data before the container pull starts.
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.manage_private_service_endpoints ? 1 : 0

  vpc_id              = local.effective_vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.interface_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.private_service_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.private_service_endpoint_common_tags,
    {
      Name             = "inca-validation-ecr-api-endpoint-${var.environment}"
      endpoint_service = "ecr-api"
      endpoint_type    = "interface"
    }
  )
}

# ECR DKR covers the Docker registry data-plane used to pull the actual image
# layers once the ECR API calls have returned the registry access details.
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.manage_private_service_endpoints ? 1 : 0

  vpc_id              = local.effective_vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.interface_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.private_service_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.private_service_endpoint_common_tags,
    {
      Name             = "inca-validation-ecr-dkr-endpoint-${var.environment}"
      endpoint_service = "ecr-dkr"
      endpoint_type    = "interface"
    }
  )
}

resource "aws_vpc_endpoint" "logs" {
  count = var.manage_private_service_endpoints ? 1 : 0

  vpc_id              = local.effective_vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.interface_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.private_service_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.private_service_endpoint_common_tags,
    {
      Name             = "inca-validation-cloudwatch-logs-endpoint-${var.environment}"
      endpoint_service = "cloudwatch-logs"
      endpoint_type    = "interface"
    }
  )
}

# STS endpoint required by the deployment runner ECS task to assume learner
# sandbox roles via sts:AssumeRole from within the private network.
resource "aws_vpc_endpoint" "sts" {
  count = var.manage_private_service_endpoints ? 1 : 0

  vpc_id              = local.effective_vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.interface_endpoint_subnet_ids
  security_group_ids  = [aws_security_group.private_service_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    local.private_service_endpoint_common_tags,
    {
      Name             = "inca-validation-sts-endpoint-${var.environment}"
      endpoint_service = "sts"
      endpoint_type    = "interface"
    }
  )
}

resource "aws_ec2_tag" "ecr_api_endpoint_enis" {
  for_each = var.manage_private_service_endpoints ? {
    for pair in setproduct(range(length(local.interface_endpoint_subnet_ids)), keys(merge(
      local.private_service_endpoint_eni_common_tags,
      {
        Name             = null
        endpoint_service = "ecr-api"
        endpoint_type    = "interface"
        vpc_endpoint_id  = aws_vpc_endpoint.ecr_api[0].id
      }
      ))) : "ecr-api:${pair[0]}:${pair[1]}" => {
      eni_index = pair[0]
      key       = pair[1]
    }
  } : {}

  resource_id = tolist(aws_vpc_endpoint.ecr_api[0].network_interface_ids)[each.value.eni_index]
  key         = each.value.key
  value = each.value.key == "Name" ? "inca-validation-ecr-api-endpoint-eni-${var.environment}-${each.value.eni_index + 1}" : merge(
    local.private_service_endpoint_eni_common_tags,
    {
      endpoint_service = "ecr-api"
      endpoint_type    = "interface"
      vpc_endpoint_id  = aws_vpc_endpoint.ecr_api[0].id
    }
  )[each.value.key]
}

resource "aws_ec2_tag" "ecr_dkr_endpoint_enis" {
  for_each = var.manage_private_service_endpoints ? {
    for pair in setproduct(range(length(local.interface_endpoint_subnet_ids)), keys(merge(
      local.private_service_endpoint_eni_common_tags,
      {
        Name             = null
        endpoint_service = "ecr-dkr"
        endpoint_type    = "interface"
        vpc_endpoint_id  = aws_vpc_endpoint.ecr_dkr[0].id
      }
      ))) : "ecr-dkr:${pair[0]}:${pair[1]}" => {
      eni_index = pair[0]
      key       = pair[1]
    }
  } : {}

  resource_id = tolist(aws_vpc_endpoint.ecr_dkr[0].network_interface_ids)[each.value.eni_index]
  key         = each.value.key
  value = each.value.key == "Name" ? "inca-validation-ecr-dkr-endpoint-eni-${var.environment}-${each.value.eni_index + 1}" : merge(
    local.private_service_endpoint_eni_common_tags,
    {
      endpoint_service = "ecr-dkr"
      endpoint_type    = "interface"
      vpc_endpoint_id  = aws_vpc_endpoint.ecr_dkr[0].id
    }
  )[each.value.key]
}

resource "aws_ec2_tag" "logs_endpoint_enis" {
  for_each = var.manage_private_service_endpoints ? {
    for pair in setproduct(range(length(local.interface_endpoint_subnet_ids)), keys(merge(
      local.private_service_endpoint_eni_common_tags,
      {
        Name             = null
        endpoint_service = "cloudwatch-logs"
        endpoint_type    = "interface"
        vpc_endpoint_id  = aws_vpc_endpoint.logs[0].id
      }
      ))) : "logs:${pair[0]}:${pair[1]}" => {
      eni_index = pair[0]
      key       = pair[1]
    }
  } : {}

  resource_id = tolist(aws_vpc_endpoint.logs[0].network_interface_ids)[each.value.eni_index]
  key         = each.value.key
  value = each.value.key == "Name" ? "inca-validation-cloudwatch-logs-endpoint-eni-${var.environment}-${each.value.eni_index + 1}" : merge(
    local.private_service_endpoint_eni_common_tags,
    {
      endpoint_service = "cloudwatch-logs"
      endpoint_type    = "interface"
      vpc_endpoint_id  = aws_vpc_endpoint.logs[0].id
    }
  )[each.value.key]
}

resource "aws_ec2_tag" "sts_endpoint_enis" {
  for_each = var.manage_private_service_endpoints ? {
    for pair in setproduct(range(length(local.interface_endpoint_subnet_ids)), keys(merge(
      local.private_service_endpoint_eni_common_tags,
      {
        Name             = null
        endpoint_service = "sts"
        endpoint_type    = "interface"
        vpc_endpoint_id  = aws_vpc_endpoint.sts[0].id
      }
      ))) : "sts:${pair[0]}:${pair[1]}" => {
      eni_index = pair[0]
      key       = pair[1]
    }
  } : {}

  resource_id = tolist(aws_vpc_endpoint.sts[0].network_interface_ids)[each.value.eni_index]
  key         = each.value.key
  value = each.value.key == "Name" ? "inca-validation-sts-endpoint-eni-${var.environment}-${each.value.eni_index + 1}" : merge(
    local.private_service_endpoint_eni_common_tags,
    {
      endpoint_service = "sts"
      endpoint_type    = "interface"
      vpc_endpoint_id  = aws_vpc_endpoint.sts[0].id
    }
  )[each.value.key]
}

resource "aws_ecs_cluster" "validation" {
  count = var.enable_validation_runtime ? 1 : 0

  name = local.ecs_cluster_name
  tags = local.common_tags
}

resource "aws_iam_role" "validation_task_execution" {
  count = var.enable_validation_runtime ? 1 : 0

  name = local.ecs_execution_role_name

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = "ecs-tasks.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "validation_task_execution_managed" {
  count = var.enable_validation_runtime ? 1 : 0

  role       = aws_iam_role.validation_task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "validation_task" {
  count = var.enable_validation_runtime ? 1 : 0

  name = local.ecs_task_role_name

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = "ecs-tasks.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )

  tags = local.common_tags
}

resource "aws_iam_role_policy" "validation_task" {
  count = var.enable_validation_runtime ? 1 : 0

  name = "inca-validation-task-policy-${var.environment}"
  role = aws_iam_role.validation_task[0].id

  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:DeleteObject",
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::${local.upload_bucket_name}/*"
        },
        {
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:UpdateItem"
          ]
          Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.upload_intents_table_name}"
        }
      ]
    }
  )
}

resource "aws_ecs_task_definition" "validation_runner" {
  count = var.enable_validation_runtime ? 1 : 0

  family                   = local.ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.validation_task_execution[0].arn
  task_role_arn            = aws_iam_role.validation_task[0].arn
  container_definitions    = local.validation_runner_container_definitions
  tags                     = local.common_tags
}

resource "aws_iam_role" "eventbridge_invoke_ecs" {
  count = var.enable_validation_runtime ? 1 : 0

  name = local.eventbridge_target_role_name

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = "events.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )

  tags = local.common_tags
}

resource "aws_iam_role_policy" "eventbridge_invoke_ecs" {
  count = var.enable_validation_runtime ? 1 : 0

  name = "inca-validation-eventbridge-invoke-policy-${var.environment}"
  role = aws_iam_role.eventbridge_invoke_ecs[0].id

  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ecs:RunTask"
          ]
          Resource = local.validation_task_definition_family_arn
          Condition = {
            ArnEquals = {
              "ecs:cluster" = aws_ecs_cluster.validation[0].arn
            }
          }
        },
        {
          Effect = "Allow"
          Action = [
            "iam:PassRole"
          ]
          Resource = [
            aws_iam_role.validation_task_execution[0].arn,
            aws_iam_role.validation_task[0].arn
          ]
        }
      ]
    }
  )
}

resource "aws_sns_topic" "validation_alerts" {
  name = "inca-validation-alerts-${var.environment}"
  tags = local.common_tags
}

resource "aws_sns_topic_policy" "validation_alerts" {
  arn = aws_sns_topic.validation_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.validation_alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "validation_alerts_email" {
  count     = var.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.validation_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_metric_filter" "validation_runner_errors" {
  count = var.enable_validation_runtime ? 1 : 0

  name           = "inca-validation-runner-errors-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.validation_runner[0].name
  pattern        = "?ERROR ?error ?FAILED ?failed"

  metric_transformation {
    name          = "ValidationRunnerErrors"
    namespace     = "INCA/Validation"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "validation_runner_errors" {
  count = var.enable_validation_runtime ? 1 : 0

  alarm_name          = "inca-validation-runner-errors-${var.environment}"
  alarm_description   = "Triggers when the validation runner ECS task logs error patterns."
  namespace           = "INCA/Validation"
  metric_name         = "ValidationRunnerErrors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.validation_alerts.arn]
  ok_actions    = [aws_sns_topic.validation_alerts.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "validation_runner" {
  count = var.enable_validation_runtime ? 1 : 0

  rule           = aws_cloudwatch_event_rule.validation_upload_trigger.name
  event_bus_name = aws_cloudwatch_event_rule.validation_upload_trigger.event_bus_name
  arn            = aws_ecs_cluster.validation[0].arn
  role_arn       = aws_iam_role.eventbridge_invoke_ecs[0].arn
  target_id      = "validation-runner"

  ecs_target {
    launch_type         = "FARGATE"
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.validation_runner[0].arn
    platform_version    = "LATEST"

    network_configuration {
      subnets          = local.effective_subnet_ids
      security_groups  = local.effective_task_security_group_ids
      assign_public_ip = var.assign_public_ip
    }
  }

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
      etag   = "$.detail.object.etag"
      region = "$.region"
    }

    input_template = <<EOF
{
  "containerOverrides": [
    {
      "name": "${local.validation_container_name}",
      "environment": [
        {"name": "VALIDATION_S3_BUCKET", "value": <bucket>},
        {"name": "VALIDATION_S3_KEY", "value": <key>},
        {"name": "VALIDATION_OBJECT_SIZE", "value": <size>},
        {"name": "VALIDATION_OBJECT_ETAG", "value": <etag>},
        {"name": "VALIDATION_EVENT_REGION", "value": <region>}
      ]
    }
  ]
}
EOF
  }
}
