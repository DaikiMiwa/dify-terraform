# ----------------------------------------------------------- #
# This file defines the ECS service for Dify API and Sandbox. #
# ----------------------------------------------------------- #

resource "aws_security_group" "dify_worker" {
  description = "Security group for Dify Worker task"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-dify-worker-001"
    }
  )
}

# Worker ingress rules
resource "aws_security_group_rule" "dify_worker_ingress_alb" {
  type                     = "ingress"
  from_port                = 5001
  to_port                  = 5001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_alb.id
  description              = "Allow inbound traffic from ALB"
  
  security_group_id = aws_security_group.dify_worker.id
}

# Worker egress rules
resource "aws_security_group_rule" "dify_worker_egress_aurora" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.aurora.id
  description              = "Allow outbound traffict to aurora"
  
  security_group_id = aws_security_group.dify_worker.id
}

resource "aws_security_group_rule" "dify_worker_egress_valkey" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.valkey.id
  description              = "Allow outbound traffict to elastic cache"
  
  security_group_id = aws_security_group.dify_worker.id
}

resource "aws_ecs_task_definition" "dify_worker" {
  family                   = "dify-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.dify_task_execution_role.arn
  task_role_arn            = aws_iam_role.dify_api_task_role.arn

  cpu    = 256
  memory = 512

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  lifecycle {
    create_before_destroy = true
  }

  # TODO : Write enviroment variables for worker tasks
  container_definitions = jsonencode([
    {
      name      = "dify-worker"
      image     = "${aws_ecr_repository.dify_api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 5002
          hostPort      = 5002
          protocol      = "tcp"
        }
      ]
      environment = [
        for name, value in {
          MODE = "worker"

          # basic settings
          CONSOLE_API_URL = "http://${aws_alb.dify_alb.dns_name}"
          CONSOLE_WEB_URL = "http://${aws_alb.dify_alb.dns_name}"
          SERVICE_API_URL = "http://${aws_alb.dify_alb.dns_name}"
          APP_API_URL     = "http://${aws_alb.dify_alb.dns_name}"
          APP_WEB_URL     = "http://${aws_alb.dify_alb.dns_name}"
          FILES_URL       = "http://${aws_alb.dify_alb.dns_name}/files"

          # PostgreSQL DB settings
          DB_HOST = aws_rds_cluster.aurora.endpoint
          DB_PORT = "5432"

          # Redis settings
          REDIS_HOST    = aws_elasticache_serverless_cache.this.endpoint[0].address
          REDIS_PORT    = "6379"
          REDIS_DB      = 0
          REDIS_USE_SSL = "true"

          # Celery settings
          CELERY_BACKEND = "redis"
          BROKER_USE_SSL = "true"

          # Storage settings
          STORAGE_TYPE           = "s3"
          S3_ENDPOINT            = "https://s3.amazonaws.com"
          AWS_REGION             = var.region
          S3_USE_AWS_MANAGED_IAM = "true"

          # Vector Store settings
          VECTOR_STORE  = "pgvector"
          PGVECTOR_HOST = aws_rds_cluster.aurora.endpoint
          PGVECTOR_PORT = "5432"

          # CORS settings
          WEB_API_CORS_ALLOW_ORIGINS = "*"
          CONSOLE_CORS_ALLOW_ORIGINS = "*"

        } : { name = name, value = tostring(value) }
      ]
      secrets = [
        for name, value in {
          # SECRET_KEY for dify
          SECRET_KEY = aws_secretsmanager_secret.dify_secret_key.arn

          # PostgreSQL DB
          DB_USERNAME = aws_rds_cluster.aurora.master_username
          DB_PASSWORD = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
          DB_DATABASE = "dify"

          # Redis Settings
          REDIS_PASSWORD = aws_secretsmanager_secret.valkey_password_secret.arn

          # Celery settings
          # The format is like redis://<redis_username>:<redis_password>@<redis_host>:<redis_port>/<redis_database>
          CELERY_BROKER_URL = "redis://${aws_elasticache_user.app_user.user_name}:${random_password.valkey_password.result}@${aws_elasticache_serverless_cache.this.endpoint[0].address}:6379/1"

          # Vector Store(pgvector same as DB)
          PGVECTOR_USER     = aws_rds_cluster.aurora.master_username
          PGVECTOR_PASSWORD = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
          PGVECTOR_DATABASE = "dify"
          PGVECTOR_PG_BIGM  = "true"

          # Storage
          S3_BUCKET_NAME = aws_s3_bucket.dify_data.bucket
        } : { name = name, valueFrom = value }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dify-worker"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "dify_worker" {
  name            = "dify-worker"
  cluster         = aws_ecs_cluster.dify.name
  desired_count   = 1
  task_definition = aws_ecs_task_definition.dify_worker.arn
  propagate_tags  = "SERVICE"
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.dify_worker.id]
  }
}

