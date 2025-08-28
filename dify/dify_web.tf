# Settings for web tasks
resource "aws_security_group" "dify_web" {
  name        = "${local.base_name}-web-001-sg"
  description = "Security group for Dify Web task"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-web-001"
    }
  )
}

# Web ingress rules
resource "aws_security_group_rule" "dify_web_ingress_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_alb.id
  description              = "Allow inbound traffic from ALB"

  security_group_id = aws_security_group.dify_web.id
}

# Web egress rules
resource "aws_security_group_rule" "dify_web_egress_aurora" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dify_web.id
  source_security_group_id = aws_security_group.aurora.id
  description              = "Aurora PostgreSQL"
}

resource "aws_security_group_rule" "dify_web_egress_valkey" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dify_web.id
  source_security_group_id = aws_security_group.valkey.id
  description              = "Valkey"
}

# VPC Endpoints への HTTPS 通信を許可
resource "aws_security_group_rule" "dify_web_egress_vpc_endpoints" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_web.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTPS to VPC endpoints for CloudWatch Logs, ECR, Secrets Manager"
}

# VPC Endpoints への HTTP 通信を許可（ECR等で必要）
resource "aws_security_group_rule" "dify_web_egress_vpc_endpoints_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_web.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTP to VPC endpoints for ECR, S3"
}

# Allow Web task to reach the internet-facing ALB over HTTP via NAT (for intra-service calls using ALB DNS)
resource "aws_security_group_rule" "dify_web_egress_http_internet" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_web.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP egress to ALB/public endpoints (required when using internet-facing ALB DNS)"
}

# S3 Gateway Endpoint access via prefix list
resource "aws_security_group_rule" "dify_web_egress_s3_prefix_list" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_web.id
  prefix_list_ids   = ["pl-61a54008"]
  description       = "Allow HTTPS to S3 via prefix list"
}

# HTTPS egress to internet when VPC endpoints are disabled
resource "aws_security_group_rule" "dify_web_egress_https_internet" {
  count             = var.enable_vpc_endpoints ? 0 : 1
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_web.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress to internet when VPC endpoints are disabled"
}

resource "aws_ecs_task_definition" "dify_web" {
  family                   = "dify-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.dify_task_execution_role.arn
  task_role_arn            = aws_iam_role.dify_web_task_role.arn

  cpu    = 256
  memory = 512

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  lifecycle {
    create_before_destroy = true
  }

  # TODO : Write enviroment variables for web tasks
  container_definitions = jsonencode([
    {
      name = "dify-web"
      # use private ECR defined above
      image     = "${aws_ecr_repository.dify_web.repository_url}:latest"
      essential = true
      environment = [
        for name, value in {
          CONSOLE_API_URL            = "https://${local.dify_fqdn}"
          APP_API_URL                = "https://${local.dify_fqdn}"
          TEXT_GENERATION_TIMEOUT_MS = 60000
        } : { name = name, value = tostring(value) }
      ]
      portMappings = [
        {
          hostPort      = 3000
          protocol      = "tcp"
          containerPort = 3000
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dify-web"
          "awslogs-create-group"  = "true"
        }
      }
      cpu         = 0
      volumesFrom = []
      mountPoints = []
    },
  ])
}


resource "aws_ecs_service" "dify_web" {
  name            = "dify-web"
  cluster         = aws_ecs_cluster.dify.name
  desired_count   = 1
  task_definition = aws_ecs_task_definition.dify_web.arn
  propagate_tags  = "SERVICE"
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.dify_web.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dify_web.arn
    container_name   = "dify-web"
    container_port   = 3000
  }

  depends_on = [
    aws_ecs_task_definition.dify_web,
    aws_lb_target_group.dify_web,
    aws_security_group.dify_web,
    aws_ecs_cluster.dify
  ]
}
