# ----------------------------------------------------------- #
# This file defines the ECS service for Dify Sandbox.       #
# ----------------------------------------------------------- #

resource "aws_security_group" "dify_sandbox" {
  name        = "${local.base_name}-sandbox-001-sg"
  description = "Security group for Dify Sandbox task"
  vpc_id      = var.vpc_id

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-sandbox-001"
    }
  )
}

# Sandbox ingress rules

resource "aws_security_group_rule" "dify_sandbox_ingress_api" {
  type                     = "ingress"
  from_port                = 8194
  to_port                  = 8194
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_api.id
  description              = "Allow inbound traffic from Dify API"

  security_group_id = aws_security_group.dify_sandbox.id
}

# Sandbox egress rules
# VPC Endpoints への HTTPS 通信を許可
resource "aws_security_group_rule" "dify_sandbox_egress_vpc_endpoints" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_sandbox.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTPS to VPC endpoints for CloudWatch Logs, ECR, Secrets Manager"
}

# VPC Endpoints への HTTP 通信を許可（ECR等で必要）
resource "aws_security_group_rule" "dify_sandbox_egress_vpc_endpoints_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_sandbox.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTP to VPC endpoints for ECR, S3"
}

# S3 Gateway Endpoint access via prefix list
resource "aws_security_group_rule" "dify_sandbox_egress_s3_prefix_list" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_sandbox.id
  prefix_list_ids   = ["pl-61a54008"]
  description       = "Allow HTTPS to S3 via prefix list"
}

# HTTPS egress to internet when VPC endpoints are disabled
resource "aws_security_group_rule" "dify_sandbox_egress_https_internet" {
  count             = var.enable_vpc_endpoints ? 0 : 1
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_sandbox.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress to internet when VPC endpoints are disabled"
}

resource "aws_ecs_task_definition" "dify_sandbox" {
  family                   = "dify-sandbox"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.dify_task_execution_role.arn
  task_role_arn            = aws_iam_role.dify_sandbox_task_role.arn

  cpu    = 256
  memory = 512

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  lifecycle {
    create_before_destroy = true
  }

  container_definitions = jsonencode([
    {
      name      = "dify-sandbox"
      image     = "${aws_ecr_repository.dify_sandbox.repository_url}:latest"
      essential = true

      portMappings = [
        {
          name          = "sandbox-port"
          hostPort      = 8194
          protocol      = "tcp"
          containerPort = 8194
        }
      ]

      environment = [
        for name, value in {
          GINE_MODE      = "release"
          WORKER_TIMEOUT = 15
          ENABLE_NETWORK = true
          SANDBOX_PORT   = 8194
        } : { name = name, value = tostring(value) }
      ]
      
      secrets = [
        {
          name      = "API_KEY"
          valueFrom = aws_secretsmanager_secret.dify_sandbox_api_key.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dify-sandbox"
        }
      }
      
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8194/health || exit 1"]
        interval    = 60
        timeout     = 10
        retries     = 3
        startPeriod = 60
      }
      
      cpu = 0
    }
  ])

  tags = merge(
    var.default_tags,
    {
      Name = "ecs-task-definition-${local.base_name}-dify-sandbox-001"
    }
  )
}

# ECS Service for Sandbox
resource "aws_ecs_service" "dify_sandbox" {
  name                   = "dify-sandbox"
  cluster                = aws_ecs_cluster.dify.name
  desired_count          = 1
  task_definition        = aws_ecs_task_definition.dify_sandbox.arn
  propagate_tags         = "SERVICE"
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.dify_sandbox.id]
    assign_public_ip = false
  }

  # Service Connect configuration
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.dify.arn

    service {
      port_name      = "sandbox-port"
      discovery_name = "sandbox"
      
      client_alias {
        port     = 8194
        dns_name = "sandbox.dify.local"
      }
    }
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecs-service-${local.base_name}-dify-sandbox-001"
    }
  )
}
