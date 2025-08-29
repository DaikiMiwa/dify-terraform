# ------------------------------------------------- #
# This file defines the ECS service for Dify API. #
# ------------------------------------------------- #
locals {
  ca_path_in_container = "${var.container_cert_mount_path}/${var.efs_ca_filename}"
  # Aurora master password will be retrieved dynamically
}

resource "aws_security_group" "dify_api" {
  name        = "${local.base_name}-api-001-sg"
  description = "Security group for Dify API task"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-api-001"
    }
  )
}

# API ingress rules
resource "aws_security_group_rule" "dify_api_ingress_alb" {
  type                     = "ingress"
  from_port                = 5001
  to_port                  = 5001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_alb.id
  description              = "Allow inbound traffic from ALB"

  security_group_id = aws_security_group.dify_api.id

  depends_on = [
    aws_security_group.dify_api,
    aws_security_group.dify_alb
  ]
}

# API egress rules

resource "aws_security_group_rule" "dify_api_egress_aurora" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.aurora.id
  description              = "Allow outbound traffic to Aurora"

  security_group_id = aws_security_group.dify_api.id
}

resource "aws_security_group_rule" "dify_api_egress_valkey" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.valkey.id
  description              = "Allow outbound traffic to Elastic Cache"

  security_group_id = aws_security_group.dify_api.id
}
resource "aws_security_group_rule" "dify_api_egress_efs" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dify_api.id
  source_security_group_id = aws_security_group.efs.id

  description = "Allow NFS traffic from ECS tasks to EFS"
}

resource "aws_security_group_rule" "dify_api_egress_plugin_daemon" {
  type                     = "egress"
  from_port                = 5002
  to_port                  = 5002
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_plugin_daemon.id
  description              = "Allow outbound traffic to plugin daemon"

  security_group_id = aws_security_group.dify_api.id
}

resource "aws_security_group_rule" "dify_api_egress_sandbox" {
  type                     = "egress"
  from_port                = 8194
  to_port                  = 8194
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_sandbox.id
  description              = "Allow outbound traffic to sandbox"

  security_group_id = aws_security_group.dify_api.id
}

# VPC Endpoints への HTTPS 通信を許可
resource "aws_security_group_rule" "dify_api_egress_vpc_endpoints" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_api.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTPS to VPC endpoints for CloudWatch Logs, ECR, Secrets Manager, Bedrock"
}

# VPC Endpoints への HTTP 通信を許可（ECR等で必要）
resource "aws_security_group_rule" "dify_api_egress_vpc_endpoints_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_api.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTP to VPC endpoints for ECR, S3"
}

# Allow API task to reach the internet-facing ALB over HTTP via NAT (for intra-service calls using ALB DNS)
resource "aws_security_group_rule" "dify_api_egress_http_internet" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_api.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP egress to ALB/public endpoints (required when using internet-facing ALB DNS)"
}

# S3 Gateway Endpoint access via prefix list
resource "aws_security_group_rule" "dify_api_egress_s3_prefix_list" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_api.id
  prefix_list_ids   = ["pl-61a54008"]
  description       = "Allow HTTPS to S3 via prefix list"
}

# HTTPS egress to internet when VPC endpoints are disabled
resource "aws_security_group_rule" "dify_api_egress_https_internet" {
  count             = var.enable_vpc_endpoints ? 0 : 1
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_api.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress to internet when VPC endpoints are disabled"
}

resource "random_password" "dify_secret_key" {
  length           = 24
  special          = true
  override_special = "!&#$^<>-"
}


# secrets for dify api
resource "aws_secretsmanager_secret" "dify_secret_key" {
  name                    = "${local.base_name}/ecs/dify/secret-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "dify_secret_key_version" {
  secret_id     = aws_secretsmanager_secret.dify_secret_key.id
  secret_string = random_password.dify_secret_key.result
}

resource "random_password" "dify_sandbox_api_key" {
  length           = 24
  special          = true
  override_special = "!&#$^<>-"
}

# secrets for dify sandbox 
resource "aws_secretsmanager_secret" "dify_sandbox_api_key" {
  name                    = "${local.base_name}/dify/sandbox-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "dify_sandbox_api_key_version" {
  secret_id     = aws_secretsmanager_secret.dify_sandbox_api_key.id
  secret_string = random_password.dify_sandbox_api_key.result
}

# Get the auto-generated master password from Aurora
data "aws_secretsmanager_secret_version" "aurora_master_password" {
  secret_id = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}

# Extract password from the JSON secret
locals {
  aurora_master_password = jsondecode(data.aws_secretsmanager_secret_version.aurora_master_password.secret_string)["password"]
}

# Create separate secret for DB password
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.base_name}/ecs/dify/db-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = local.aurora_master_password
}

# SQL URI secret
locals {
  db_user_enc = urlencode(aws_rds_cluster.aurora.master_username)
  db_pass_enc = urlencode(local.aurora_master_password)

  sql_uri = "postgresql+psycopg2://${local.db_user_enc}:${local.db_pass_enc}@${aws_rds_cluster.aurora.endpoint}:5432/${aws_rds_cluster.aurora.database_name}?sslmode=verify-full&sslrootcert=${local.ca_path_in_container}"
}


resource "aws_secretsmanager_secret" "sql_uri" {
  name                    = "${local.base_name}/ecs/dify/sql-uri"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "sql_uri_version" {
  secret_id     = aws_secretsmanager_secret.sql_uri.id
  secret_string = local.sql_uri
}

resource "aws_ecs_task_definition" "dify_api" {
  family                   = "dify-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.dify_task_execution_role.arn
  task_role_arn            = aws_iam_role.dify_api_task_role.arn

  cpu    = 512
  memory = 1024

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

  # TODO: Write enviroment variables for api task
  container_definitions = jsonencode([
    {
      name = "dify-api"
      # use private ECR defined above
      # The image is defined in the ECR repository created above
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
          MODE = "api"

          # basic settings
          CONSOLE_API_URL = "https://${local.dify_fqdn}"
          CONSOLE_WEB_URL = "https://${local.dify_fqdn}"
          SERVICE_API_URL = "https://${local.dify_fqdn}"
          APP_API_URL     = "https://${local.dify_fqdn}"
          APP_WEB_URL     = "https://${local.dify_fqdn}"
          FILES_URL       = "https://${local.dify_fqdn}"

          # PostgreSQL DB settings
          DB_HOST = aws_rds_cluster.aurora.endpoint
          DB_PORT = "5432"

          # Redis settings (for general use)
          REDIS_HOST     = aws_elasticache_replication_group.this.primary_endpoint_address
          REDIS_PORT     = "6379"
          REDIS_DB       = 0
          REDIS_USE_SSL  = "true"

          # Celery settings (using shared ElastiCache with DB 1)
          CELERY_BACKEND = "redis"

          # Debug settings
          LOG_LEVEL = "DEBUG"

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
          CODE_EXECUTION_ENDPOINT = "http://sandbox.dify.local:8194"

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

          # migration settings
          MIGRATION_ENABLED = "true"

          # DEBUG
          DEBUG                  = "true"
          ENABLE_REQUEST_LOGGING = "true"
          SQLALCHEMY_ECHO        = "false"

          # plugin daemon settings
          PLUGIN_DAEMON_PORT = 5002
          PLUGIN_DAEMON_URL  = "http://plugin-daemon.dify.local:5002"
        } : { name = name, value = tostring(value) }
      ]
      secrets = [
        for name, value in {
          # SECRET_KEY for dify
          SECRET_KEY = aws_secretsmanager_secret.dify_secret_key.arn

          # PostgreSQL DB - secret values only
          DB_PASSWORD = aws_secretsmanager_secret.db_password.arn

          # Redis Settings
          REDIS_PASSWORD = aws_secretsmanager_secret.valkey_default_password_secret.arn

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
          "awslogs-stream-prefix" = "dify-api"
          "awslogs-create-group"  = "true"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5001/health || exit 1"]
        interval    = 30
        timeout     = 30
        retries     = 5
        startPeriod = 120
      }
      cpu = 0
    }
  ])

  tags = merge(
    var.default_tags,
    {
      Name = "ecs-task-definition-${local.base_name}-dify-api-001"
    }
  )
}

# ECS Service
resource "aws_ecs_service" "dify_api" {
  depends_on             = [aws_lb_listener_rule.dify_api_basic, aws_lb_listener_rule.dify_api_v1]
  name                   = "dify-api"
  cluster                = aws_ecs_cluster.dify.name
  desired_count          = 1
  task_definition        = aws_ecs_task_definition.dify_api.arn
  propagate_tags         = "SERVICE"
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.dify_api.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dify_api.arn
    container_name   = "dify-api"
    container_port   = 5001
  }

  # Service Connect configuration (client mode)
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.dify.arn
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecs-service-${local.base_name}-dify-api-001"
    }
  )
}
