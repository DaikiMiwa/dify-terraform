# -------------------------------------
# Setting for aurora serverless cluster
# -------------------------------------
resource "aws_security_group" "aurora" {
  description = "Security group for Aurora Serverless cluster"
  vpc_id      = aws_vpc.this.id

  ingress = {
    from_port          = 5432
    to_port            = 5432
    protocol           = "tcp"
    security_group_ids = [aws_security_group.dify_api.id, aws_security_group.dify_worker.id]
  }

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-aurora-001"
    }
  )
}

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "aurora-cluster-parameter-group-${local.base_name}-001"
  family      = "aurora-postgresql15"
  description = "Aurora cluster parameter group for ${local.base_name}"

  # Enforce ssl connection to meets secrurity requirements in ACN
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = merge(
    var.default_tags,
    {
      Name = "rds-cluster-parameter-group-${local.base_name}-001"
    }
  )
}

resource "aws_db_subnet_group" "aurora" {
  name       = "aurora-subnet-group-${local.base_name}-001"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.default_tags,
    {
      Name = "rds-subnet-group-${local.base_name}-001"
    }
  )
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier   = "aurora-cluster-${local.base_name}-001"
  engine               = "aurora-postgresql"
  engine_mode          = "provisioned"
  database_name        = "dify"
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  master_username             = "dbadmin"
  manage_master_user_password = true

  storage_encrypted = true

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    max_capacity             = var.aws_rds_cluster_scaling_configuration.max_capacity
    min_capacity             = var.aws_rds_cluster_scaling_configuration.min_capacity
    seconds_until_auto_pause = var.aws_rds_cluster_scaling_configuration.seconds_until_auto_pause
  }

  tags = merge(
    var.default_tags,
    {
      Name = "rds-cluster-${local.base_name}-001"
    }
  )
}

resource "aws_rds_cluster_instance" "aurora_instance" {

  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  performance_insights_enabled = true

  tags = merge(
    var.default_tags,
    {
      Name = "rds-cluster-instance-${local.base_name}-001"
    }
  )
}

# ------------------------------------------------
# Settings for Elastic Cache Serverless for Valkey
# ------------------------------------------------

resource "aws_security_group" "valkey" {
  description = "Security group for Valkey Serverless cluster"
  vpc_id      = aws_vpc.this.id

  # Allow inbound traffic from private subnets
  ingress {
    description     = "Allow inbound traffic from private subnets"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.dify_api.id, aws_security_group.dify_worker.id]
  }

  ingress {
    description     = "Allow inbound traffic from ECS tasks"
    from_port       = 6380
    to_port         = 6380
    protocol        = "tcp"
    security_groups = [aws_security_group.dify_api.id, aws_security_group.dify_worker.id]
  }

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-valkey-001"
    }
  )
}

# settings for valkey user for dify
resource "random_password" "valkey_password" {
  length           = 24
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "valkey_password_secret" {
  name = "elasticache/valkey/app-user-password"
}

resource "aws_secretsmanager_secret_version" "valkey_password_secret_version" {
  secret_id     = aws_secretsmanager_secret.valkey_password_secret.id
  secret_string = random_password.valkey_password.result
}

resource "aws_elasticache_user" "app_user" {
  user_id   = "dify-id"
  user_name = "dify"
  engine    = "valkey" # もしエラーになる古いProviderなら "redis" を一時的に使用

  # 例: すべてのキーに対して危険コマンド以外を許可
  access_string = "on ~* +@all -@dangerous"

  authentication_mode {
    type      = "password"
    passwords = [random_password.valkey_pwd.result]
    # パスワードローテ時は2個まで並行設定可（入替→古い方を外す）
  }

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-user-${local.base_name}-001"
    }
  )
}

resource "aws_elasticache_user_group" "app_user_group" {
  user_group_id = "dify-user-group"
  engine        = "valkey"

  user_ids = [aws_elasticache_user.app_user.user_id]

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-user-group-${local.base_name}-001"
    }
  )
}

resource "aws_elasticache_serverless_cache" "this" {
  engine = "valkey"
  name   = "es-${local.base_name}-001"

  description          = "Elastic Cache Serverless for Valkey"
  major_engine_version = "8"
  user_group_id        = aws_elasticache_user_group.app_user_group.id

  # We need to set the limits to 100 MG at manual after resource creation by terraform
  cache_usage_limits {
    data_storage {
      maximum = "1"
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 1000
    }
  }

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.valkey.id]

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-serverless-${local.base_name}-001"
    }
  )
}

# ------------------------------------------------
# Settings for S3
# ------------------------------------------------
resource "aws_s3_bucket" "dify_data" {
  bucket = "dify-data-${local.base_name}-001"

  tags = merge(
    var.default_tags,
    {
      Name = "s3-bucket-${local.base_name}-dify-data-001"
    }
  )
}

# Block public access to meets security standards in ACN
resource "aws_s3_bucket_public_access_block" "dify_data" {
  bucket = aws_s3_bucket.dify_data.id

  block_public_acls       = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  block_public_policy     = true
}

# Apply 
resource "aws_s3_bucket_server_side_encryption_configuration" "dify_data" {
  bucket = aws_s3_bucket.dify_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "dify_data" {
  # HTTP拒否（TLS必須）
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.dify_data.arn, "${aws_s3_bucket.dify_data.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "dify_data" {
  bucket = aws_s3_bucket.dify_data.id
  policy = data.aws_iam_policy_document.dify_data.json
  depends_on = [
    aws_s3_bucket_public_access_block.dify_data,
    aws_s3_bucket_server_side_encryption_configuration.dify_data
  ]
}

# s3 endpoint for VPC
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id       = aws_vpc.this.id
#   service_name = "com.amazonaws.${var.region}.s3"
# 
#   route_table_ids = [
# 
#   ]
# }

# ------------------------------------------------
# Settings for ECR
# ------------------------------------------------
# private ecr for dify containers 
resource "aws_ecr_repository" "dify_web" {
  name                 = "${local.base_name}/dify-web"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecr-repo-${local.base_name}-dify-web-001"
    }
  )
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_api" {
  name                 = "${local.base_name}/dify-api"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecr-repo-${local.base_name}-dify-api-001"
    }
  )
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_sandbox" {
  name                 = "${local.base_name}/dify-sandbox"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecr-repo-${local.base_name}-dify-sandbox-001"
    }
  )
}

# ------------------------------------------------
# Settings for ECS
# ------------------------------------------------
resource "aws_ecs_cluster" "dify" {
  name = "ecs-cluster-${local.base_name}-001"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "ecs-cluster-${local.base_name}-001"
  }
}

# define the cloudwatch log group for ECS tasks
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/dify"
  retention_in_days = 7

  tags = merge(
    var.default_tags,
    {
      Name = "cloudwatch-log-group-${local.base_name}-dify-001"
    }
  )
}

# define the task execution role for ECS tasks
# TODO: Need review for the permissions
data "aws_iam_policy_document" "dify_task_execution_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "dify_task_execution_policy" {
  statement {
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListAllMyBuckets",
      "bedrock:invokeModel",
      "bedrock:invokeModelWithResponseStream"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role" "dify_task_execution_role" {
  name               = "dify-task-execution-role-${local.base_name}-001"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags = merge(
    var.default_tags,
    {
      Name = "iam-role-${local.base_name}-dify-task-execution-001"
    }
  )
}

resource "aws_iam_role_policy" "dify_task_execution_policy" {
  name   = "dify-task-execution-policy-${local.base_name}-001"
  role   = aws_iam_role.dify_task_execution_role.id
  policy = data.aws_iam_policy_document.dify_task_execution_policy.json
}

# We need tasks for web, api and worker at minimum
# api task and worker task are required for the same role 
# Bedrock, S3, CloudWatch Logs is required
# TODO: Add ssm permission
data "aws_iam_policy_document" "dify_api_task_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.dify_data.arn,
      "${aws_s3_bucket.dify_data.arn}/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "bedrock:invokeModel",
      "bedrock:invokeModelWithResponseStream",
    ]

    resources = [
      "*"
    ]
  }
}

data "aws_iam_policy_document" "dify_api_task_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "dify_api_task_role" {
  name               = "dify-api-task-role-${local.base_name}-001"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(
    var.default_tags,
    {
      Name = "iam-role-${local.base_name}-dify-api-task-001"
    }
  )
}

resource "aws_iam_role_policy" "dify_api_task_policy" {
  name   = "dify-api-task-policy-${local.base_name}-001"
  role   = aws_iam_role.dify_api_task_role.id
  policy = data.aws_iam_policy_document.dify_api_task_policy.json
}

resource "aws_security_group" "dify_api" {
  description = "Security group for Dify API task"
  vpc_id      = aws_vpc.this.id

  # TODO
  # need ingress from ALB and 
  ingress {
    description     = "Allow inbound traffic from ALB"
    from_port       = 5001
    to_port         = 5001
    protocol        = "tcp"
    security_groups = [aws_security_group.dify_alb.id]
  }

  egress {
    description     = "Allow outbound traffic to Aurora"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.aurora.id]
  }

  egress {
    description     = "Allow outbound traffic to Elastic Cache"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.valkey.id]
  }

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-dify-api-001"
    }
  )
}

resource "random_password" "dify_secret_key" {
  length           = 24
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "dify_secret_key" {
  name = "ecs/dify/secret-key"
}

resource "aws_secretsmanager_secret_version" "dify_secret_key_version" {
  secret_id     = aws_secretsmanager_secret.dify_secret_key.id
  secret_string = random_password.dify_secret_key.result
}

resource "aws_ecs_task_definition" "dify_api" {
  family                   = "dify-api"
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

  # TODO: Write enviroment variables for api task
  container_definitions = jsonencode([
    {
      name = "dify-api"
      # use private ECR defined above
      # The image is defined in the ECR repository created above
      image     = "${aws_ecr_repository.dify_api.repository_url}${var.dify_api_version}"
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
          CONSOLE_API_URL = "http://${aws_alb.dify_alb.dns_name}"
          CONSOLE_WEB_URL = "http://${aws_lb.dify_web.dns_name}"
          SERVICE_API_URL = "http://${aws_lb.dify_api.dns_name}"
          APP_API_URL     = "http://${aws_lb.dify_api.dns_name}"
          APP_WEB_URL     = "http://${aws_lb.dify_web.dns_name}"
          FILES_URL       = "http://${aws_lb.dify_api.dns_name}/files"

          # PostgreSQL DB settings
          DB_HOST = aws_rds_cluster.aurora.endpoint
          DB_PORT = "5432"

          # Redis settings
          REDIS_HOST    = aws_elasticache_serverless_cache.this.cache_endpoint
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
          CERELY_BROKER_URL = "redis://${aws_elasticache_user.app_user.user_name}:${random_password.valkey_password.result}@${aws_elasticache_serverless_cache.this.cache_endpoint}:6379/1"

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
          "awslogs-stream-prefix" = "dify-api"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5001/health || exit 1"]
        interval    = 60
        timeout     = 10
        retries     = 3
        startPeriod = 60
      }
      cpu         = 0
      volumesFrom = []
      mountPoints = []
    },
    {
      name      = "dify-sandbox"
      image     = "${aws_ecr_repository.dify_sandbox.repository_url}:latest"
      essential = true

      portMappings = [
        {
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
          valueFrom = aws_secretsmanager_secret.dify_secret_key.arn
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
      cpu        = 0
      volumeFrom = []
    }
  ])

  tags = merge(
    var.default_tags,
    {
      Name = "ecs-task-definition-${local.base_name}-dify-api-001"
    }
  )
}

# Settings for worker task
resource "aws_security_group" "dify_worker" {
  description = "Security group for Dify Worker task"
  vpc_id      = aws_vpc.this.id

  # TODO:
  ingress {
    description     = "Allow inbound traffic from ALB"
    from_port       = 5001
    to_port         = 5001
    protocol        = "tcp"
    security_groups = [aws_security_group.dify_alb.id]
  }

  # TODO: outbound for interact with elastic cache and aurora
  egress {
    description     = "Allow outbound traffict to aurora"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.aurora.id]
  }

  egress {
    description     = "Allow outbound traffict to elastic cache"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.valkey.id]
  }

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-dify-worker-001"
    }
  )
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
      image     = "langgenius/dify-worker${var.dify_api_version}"
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
          REDIS_HOST    = aws_elasticache_serverless_cache.this.cache_endpoint
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

          # Code execution settings
          CODE_EXECUTION_ENDPOINT = "https://localhost:8194" # cotainers in tasks share the same network

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
          CERELY_BROKER_URL = "redis://${aws_elasticache_user.app_user.user_name}:${random_password.valkey_password.result}@${aws_elasticache_serverless_cache.this.cache_endpoint}:6379/1"

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

# Settings for web tasks
resource "aws_security_group" "dify_web" {
  description = "Security group for Dify Web task"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Allow inbound traffic from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.dify_alb.id]
  }

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-dify-web-001"
    }
  )
}

resource "aws_ecs_task_definition" "dify_web" {
  family                   = "dify-web"
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
          APP_API_URL                = "http://${aws_lb.dify.dns_name}"
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
          "awslogs-group"         = aws_cloudwatch_log_group.dify.name
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

# ECS Service
resource "aws_ecs_service" "dify_api" {
  depends_on      = [aws_lb_listener_rule.dify_api]
  name            = "dify-api"
  cluster         = aws_ecs_cluster.dify.name
  desired_count   = 1
  task_definition = aws_ecs_task_definition.dify_api.arn
  propagate_tags  = "SERVICE"
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.dify_api.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dify_api.arn
    container_name   = "dify-api"
    container_port   = 5001
  }
}

resource "aws_ecs_service" "dify_worker" {
  name            = "dify-worker"
  cluster         = aws_ecs_cluster.dify.name
  desired_count   = 1
  task_definition = aws_ecs_task_definition.dify_worker.arn
  propagate_tags  = "SERVICE"
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.dify_worker.id]
  }
}

resource "aws_ecs_service" "dify_web" {
  name            = "dify-web"
  cluster         = aws_ecs_cluster.dify.name
  desired_count   = 1
  task_definition = aws_ecs_task_definition.dify_worker.arn
  propagate_tags  = "SERVICE"
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups = [aws_security_group.dify_web.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dify_web.arn
    container_name   = "dify-web"
    container_port   = 3000
  }
}

# ------------------------------------------------
# Settings for Application Load balancer for ecs
# ------------------------------------------------
resource "aws_security_group" "dify_alb" {
  description = "Security group for Dify ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
    description = "Allow inbound traffic on port 80 from private subnet cidr blocks"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
    description = "Allow inbound traffic on port 443 from private subnet cidr blocks"
  }

  egress {
    from_port = 3000
    to_port   = 3000
    protocol  = "tcp"
    # Allow outbound traffic to web tasks
    security_groups = [aws_security_group.dify_web.id]
    description     = "Allow outbound traffic to web tasks"
  }

  egress {
    from_port = 5001
    to_port   = 5001
    protocol  = "tcp"
    # Allow outbound traffic to api tasks
    security_groups = [aws_security_group.dify_api.id]
    description     = "Allow outbound traffic to api tasks"
  }

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-dify-alb-001"
    }
  )
}

resource "aws_alb" "dify_alb" {
  name               = "alb-dify"
  internal           = true
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.dify_alb.id
  ]
  subnets = [aws_subnet.public.id]

  enable_deletion_protection = false

  tags = merge(
    var.default_tags,
    {
      Name = "alb-${local.base_name}-dify-001"
    }
  )
}

# TODO: Need review
resource "aws_lb_target_group" "dify_api" {
  name     = "tg-dify-api"
  port     = 5001
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

}

resource "aws_lb_target_group" "dify_web" {
  name     = "tg-dify-web"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(
    var.default_tags,
    {
      Name = "tg-${local.base_name}-dify-web-001"
    }
  )
}

# HTTPで入力を受け付けて、Webタスクに転送するリスナーを作成
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_alb.dify_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_web.arn
  }

  tags = merge(
    var.default_tags,
    {
      Name = "alb-listener-${local.base_name}-dify-001"
    }
  )
}

# Use path base routing to forward requests to the api target group
locals {
  api_paths = ["/console/api", "/api", "/v1", "/files"]
}

resource "aws_lb_listener_rule" "dify_api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = local.api_paths
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_api.arn
  }

  tags = merge(
    var.default_tags,
    {
      Name = "dify-api-listener-rule-${local.base_name}-001"
    }
  )
}

resource "aws_lb_listener_rule" "dify_api_routing" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 11

  condition {
    path_pattern {
      values = [for path in local.api_paths : "${path}/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_api.arn
  }

  tags = merge(
    var.default_tags,
    {
      Name = "dify-api-routing-listener-rule-${local.base_name}-001"
    }
  )
}
