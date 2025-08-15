# Settings for web tasks
resource "aws_security_group" "dify_web" {
  description = "Security group for Dify Web task"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-dify-web-001"
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
          CONSOLE_API_URL            = "http://${aws_alb.dify_alb.dns_name}"
          APP_API_URL                = "http://${aws_alb.dify_alb.dns_name}"
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
  task_definition = aws_ecs_task_definition.dify_worker.arn
  propagate_tags  = "SERVICE"
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.dify_web.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dify_web.arn
    container_name   = "dify-web"
    container_port   = 3000
  }
}
