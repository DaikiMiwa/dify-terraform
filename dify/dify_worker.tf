# ----------------------------------------------------------- #
# This file defines the ECS service for Dify API and Sandbox. #
# ----------------------------------------------------------- #

resource "aws_security_group" "dify_worker" {
  name        = "${local.base_name}-worker-001-sg"
  description = "Security group for Dify Worker task"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-worker-001"
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

resource "aws_security_group_rule" "dify_worker_egress_efs" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dify_worker.id
  source_security_group_id = aws_security_group.efs.id

  description = "Allow NFS traffic from ECS tasks to EFS"
}

# VPC Endpoints への HTTPS 通信を許可
resource "aws_security_group_rule" "dify_worker_egress_vpc_endpoints" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_worker.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTPS to VPC endpoints for CloudWatch Logs, ECR, Secrets Manager, Bedrock"
}

# VPC Endpoints への HTTP 通信を許可（ECR等で必要）
resource "aws_security_group_rule" "dify_worker_egress_vpc_endpoints_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_worker.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTP to VPC endpoints for ECR, S3"
}

# Allow Worker task to reach the internet-facing ALB over HTTP via NAT (for intra-service calls using ALB DNS)
resource "aws_security_group_rule" "dify_worker_egress_http_internet" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_worker.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP egress to ALB/public endpoints (required when using internet-facing ALB DNS)"
}

# S3 Gateway Endpoint access via prefix list
resource "aws_security_group_rule" "dify_worker_egress_s3_prefix_list" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_worker.id
  prefix_list_ids   = ["pl-61a54008"]
  description       = "Allow HTTPS to S3 via prefix list"
}

# HTTPS egress to internet when VPC endpoints are disabled
resource "aws_security_group_rule" "dify_worker_egress_https_internet" {
  count             = var.enable_vpc_endpoints ? 0 : 1
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_worker.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress to internet when VPC endpoints are disabled"
}

resource "aws_ecs_task_definition" "dify_worker" {
  family                   = "dify-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.dify_task_execution_role.arn
  task_role_arn            = aws_iam_role.dify_api_task_role.arn

  cpu    = 1024
  memory = 2048

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  lifecycle {
    create_before_destroy = true
  }

  volume {
    name = "efs-certs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.certs.id
        iam             = "ENABLED"
      }
    }
  }

  # TODO : Write enviroment variables for worker tasks
  container_definitions = jsonencode([
    {
      name      = "dify-worker"
      image     = "${aws_ecr_repository.dify_api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 5001
          hostPort      = 5001
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
          FILES_URL       = "http://${aws_alb.dify_alb.dns_name}"

          # PostgreSQL DB settings
          DB_HOST = aws_rds_cluster.aurora.endpoint
          DB_PORT = "5432"

          # Redis settings (for general use)
          REDIS_HOST     = aws_elasticache_replication_group.this.primary_endpoint_address
          REDIS_PORT     = "6379"
          REDIS_DB       = 0
          REDIS_USE_SSL  = "true"
          REDIS_USERNAME = aws_elasticache_user.app_user.user_name

          # Celery settings (using shared ElastiCache with DB 1)
          CELERY_BACKEND = "redis"

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

          # code execution endpoint
          CODE_EXECUTION_ENDPOINT = "http://${aws_alb.dify_alb.dns_name}"

          # PostgreSQL DB - non-secret values
          DB_USERNAME   = aws_rds_cluster.aurora.master_username
          DB_DATABASE   = aws_rds_cluster.aurora.database_name
          PGSSLMODE     = "verify-full"
          PGSSLROOTCERT = "${local.ca_path_in_container}"

          # Vector Store(pgvector same as DB) - non-secret values
          PGVECTOR_USER     = aws_rds_cluster.aurora.master_username
          PGVECTOR_DATABASE = aws_rds_cluster.aurora.database_name
          PGVECTOR_PG_BIGM  = "true"

          # Storage
          S3_BUCKET_NAME = aws_s3_bucket.dify_data.bucket

          # DEBUG
          LOG_LEVEL              = "DEBUG"
          DEBUG                  = "true"
          ENABLE_REQUEST_LOGGING = "true"
          SQLALCHEMY_ECHO        = "true"

          # plugin daemon settings
          PLUGIN_DAEMON_PORT = 80
          PLUGIN_DAEMON_URL  = "http://${aws_alb.dify_alb.dns_name}"
        } : { name = name, value = tostring(value) }
      ]
      secrets = [
        for name, value in {
          # SECRET_KEY for dify
          SECRET_KEY = aws_secretsmanager_secret.dify_secret_key.arn

          # PostgreSQL DB - secret values only
          DB_PASSWORD = aws_secretsmanager_secret.db_password.arn

          # SQL URI with SSL certificate
          # SQLALCHEMY_DATABASE_URI = aws_secretsmanager_secret.sql_uri.arn

          # Redis Settings
          REDIS_PASSWORD = aws_secretsmanager_secret.valkey_password_secret.arn

          # Celery settings
          # The format is like redis://<redis_username>:<redis_password>@<redis_host>:<redis_port>/<redis_database>
          CELERY_BROKER_URL = aws_secretsmanager_secret.celery_broker_url_secret.arn

          # Vector Store(pgvector same as DB) - secret values only
          PGVECTOR_PASSWORD = aws_secretsmanager_secret.db_password.arn

          # code execution settings
          CODE_EXECUTION_API_KEY = aws_secretsmanager_secret.dify_sandbox_api_key.arn

          # PLUGIN daemon settings
          PLUGIN_DAEMON_KEY = aws_secretsmanager_secret.dify_sandbox_api_key.arn

        } : { name = name, valueFrom = value }
      ]
      mountPoints = [
        {
          sourceVolume  = "efs-certs",
          containerPath = var.container_cert_mount_path,
          readOnly      = true
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dify-worker"
          "awslogs-create-group"  = "true"
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
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.dify_worker.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_ecs_task_definition.dify_worker,
    aws_security_group.dify_worker,
    aws_ecs_cluster.dify
  ]
}

