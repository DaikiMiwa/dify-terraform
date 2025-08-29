# ----------------------------------------------------------- #
# This file defines the ECS service for Dify Plugin Daemon. #
# ----------------------------------------------------------- #

# Security Group for Plugin Daemon
resource "aws_security_group" "dify_plugin_daemon" {
  name        = "${local.base_name}-plugin-daemon-001-sg"
  description = "Security group for Dify Plugin Daemon task"
  vpc_id      = var.vpc_id

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-plugin-daemon-001"
    }
  )
}

# Plugin Daemon ingress rules

resource "aws_security_group_rule" "dify_plugin_daemon_ingress_api" {
  type                     = "ingress"
  from_port                = 5002
  to_port                  = 5002
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_api.id
  description              = "Allow inbound traffic from dify-api tasks"

  security_group_id = aws_security_group.dify_plugin_daemon.id
}

resource "aws_security_group_rule" "dify_plugin_daemon_ingress_worker" {
  type                     = "ingress"
  from_port                = 5002
  to_port                  = 5002
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_worker.id
  description              = "Allow inbound traffic from dify-worker tasks"

  security_group_id = aws_security_group.dify_plugin_daemon.id
}


# Plugin Daemon egress rules

resource "aws_security_group_rule" "dify_plugin_daemon_egress_aurora" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.aurora.id
  description              = "Allow outbound traffic to Aurora"

  security_group_id = aws_security_group.dify_plugin_daemon.id
}

resource "aws_security_group_rule" "dify_plugin_daemon_egress_valkey" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.valkey.id
  description              = "Allow outbound traffic to Elastic Cache"

  security_group_id = aws_security_group.dify_plugin_daemon.id
}

resource "aws_security_group_rule" "dify_plugin_daemon_egress_efs_certs" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dify_plugin_daemon.id
  source_security_group_id = aws_security_group.efs.id

  description = "Allow NFS traffic from ECS tasks to EFS (certs)"
}

resource "aws_security_group_rule" "dify_plugin_daemon_egress_efs_plugins" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dify_plugin_daemon.id
  source_security_group_id = aws_security_group.efs_plugins.id

  description = "Allow NFS traffic from ECS tasks to EFS (plugins)"
}

resource "aws_security_group_rule" "dify_plugin_daemon_egress_api" {
  type                     = "egress"
  from_port                = 5001
  to_port                  = 5001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_api.id
  description              = "Allow outbound traffic to dify-api tasks"

  security_group_id = aws_security_group.dify_plugin_daemon.id
}

# VPC Endpoints への HTTPS 通信を許可
resource "aws_security_group_rule" "dify_plugin_daemon_egress_vpc_endpoints" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_plugin_daemon.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTPS to VPC endpoints for CloudWatch Logs, ECR, Secrets Manager"
}

# VPC Endpoints への HTTP 通信を許可（ECR等で必要）
resource "aws_security_group_rule" "dify_plugin_daemon_egress_vpc_endpoints_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_plugin_daemon.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTP to VPC endpoints for ECR, S3"
}

# Allow Plugin Daemon task to reach the internet-facing ALB over HTTP via NAT (for intra-service calls using ALB DNS)
resource "aws_security_group_rule" "dify_plugin_daemon_egress_http_internet" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_plugin_daemon.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP egress to ALB/public endpoints (required when using internet-facing ALB DNS)"
}

# S3 Gateway Endpoint access via prefix list
resource "aws_security_group_rule" "dify_plugin_daemon_egress_s3_prefix_list" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_plugin_daemon.id
  prefix_list_ids   = ["pl-61a54008"]
  description       = "Allow HTTPS to S3 via prefix list"
}

# HTTPS egress to internet when VPC endpoints are disabled
resource "aws_security_group_rule" "dify_plugin_daemon_egress_https_internet" {
  count             = var.enable_vpc_endpoints ? 0 : 1
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_plugin_daemon.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress to internet when VPC endpoints are disabled"
}

# IAM Role for Plugin Daemon Task
resource "aws_iam_role" "dify_plugin_daemon_task_role" {
  name = "${local.base_name}-plugin-daemon-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.default_tags,
    {
      Name = "iam-role-${local.base_name}-plugin-daemon-task-001"
    }
  )
}

resource "aws_iam_role_policy" "dify_plugin_daemon_task_policy" {
  name = "${local.base_name}-plugin-daemon-task-policy"
  role = aws_iam_role.dify_plugin_daemon_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.dify_data.arn,
          "${aws_s3_bucket.dify_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.dify_secret_key.arn,
          aws_secretsmanager_secret.dify_sandbox_api_key.arn,
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.valkey_default_password_secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetInferenceProfile",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:*:inference-profile/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:Rerank"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# ECS Task Definition for Plugin Daemon
resource "aws_ecs_task_definition" "dify_plugin_daemon" {
  family                   = "dify-plugin-daemon"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.dify_task_execution_role.arn
  task_role_arn            = aws_iam_role.dify_plugin_daemon_task_role.arn

  cpu    = 256
  memory = 512

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

  volume {
    name = "efs-plugins"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.plugins.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.plugins.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "dify-plugin-daemon"
      image     = "${aws_ecr_repository.dify_plugin_daemon.repository_url}:latest"
      essential = true

      portMappings = [
        {
          name          = "plugin-daemon-port"
          hostPort      = 5002
          containerPort = 5002
          protocol      = "tcp"
        },
        {
          hostPort      = 5003
          containerPort = 5003
          protocol      = "tcp"
        }
      ]

      environment = [
        for name, value in {
          # Plugin daemon settings
          SERVER_PORT        = 5002
          GIN_MODE           = "release"
          DIFY_INNER_API_URL = "http://${aws_alb.dify_alb.dns_name}"

          # PostgreSQL DB settings
          DB_HOST        = aws_rds_cluster.aurora.endpoint
          DB_PORT        = "5432"
          DB_USERNAME    = aws_rds_cluster.aurora.master_username
          DB_DATABASE    = aws_rds_cluster.aurora.database_name
          DB_SSL_MODE    = "require"
          SSLMODE        = "verify-full"
          DB_SSLROOTCERT = local.ca_path_in_container

          # Storage settings
          STORAGE_TYPE             = "s3"
          S3_ENDPOINT              = "https://s3.amazonaws.com"
          S3_BUCKET                = aws_s3_bucket.dify_data.bucket
          S3_BUCKET_NAME           = aws_s3_bucket.dify_data.bucket
          PLUGIN_STORAGE_OSS_BUCKET=aws_s3_bucket.dify_data.bucket
          PLUGIN_S3_BUCKET_NAME           = aws_s3_bucket.dify_data.bucket
          AWS_REGION               = var.region
          S3_USE_AWS_MANAGED_IAM   = "true"
          S3_USE_AWS               = "true"
          
          REDIS_SSL_CERT_REQS      = "required"
          REDIS_SSL_CHECK_HOSTNAME = "true"

          PLUGIN_REMOTE_INSTALLING_HOST = "0.0.0.0"
          PLUGIN_REMOTE_INSTALLING_PORT = 5003
          PLUGIN_WORKING_PATH           = "/app/storage/plugins"

          # Redis settings
          REDIS_HOST     = aws_elasticache_replication_group.this.primary_endpoint_address
          REDIS_PORT     = "6379"
          REDIS_DB       = 0
          REDIS_USE_SSL  = "true"

        } : { name = name, value = tostring(value) }
      ]

      secrets = [
        {
          name      = "SERVER_KEY"
          valueFrom = aws_secretsmanager_secret.dify_sandbox_api_key.arn
        },
        {
          name      = "DIFY_INNER_API_KEY"
          valueFrom = aws_secretsmanager_secret.dify_secret_key.arn
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = aws_secretsmanager_secret.valkey_default_password_secret.arn
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "efs-certs",
          containerPath = var.container_cert_mount_path,
          readOnly      = true
        },
        {
          sourceVolume  = "efs-plugins",
          containerPath = "/app/storage/plugins",
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dify-plugin-daemon"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5002/health/check || exit 1"]
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
      Name = "ecs-task-definition-${local.base_name}-dify-plugin-daemon-001"
    }
  )
}

# ECS Service for Plugin Daemon
resource "aws_ecs_service" "dify_plugin_daemon" {
  name                   = "dify-plugin-daemon"
  cluster                = aws_ecs_cluster.dify.name
  desired_count          = 1
  task_definition        = aws_ecs_task_definition.dify_plugin_daemon.arn
  propagate_tags         = "SERVICE"
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.dify_plugin_daemon.id]
    assign_public_ip = false
  }

  # Service Connect configuration
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.dify.arn

    service {
      port_name      = "plugin-daemon-port"
      discovery_name = "plugin-daemon"
      
      client_alias {
        port     = 5002
        dns_name = "plugin-daemon.dify.local"
      }
    }
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecs-service-${local.base_name}-dify-plugin-daemon-001"
    }
  )
}
