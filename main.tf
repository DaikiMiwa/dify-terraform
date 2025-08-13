# Network Infrastructure with VPC, Subnets, NAT Gateway, and Flow Logs

data "aws_iam_policy_document" "flow_log_policy" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeGroups",
      "logs:DescribeLogStreams"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = ["ec2:DescribeVpcs"]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}


resource "aws_iam_role" "vpc_flow_log" {
  name               = "vpc-flow-log-role-${local.base_name}-001"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = "vpc-flow-log-role-${local.base_name}-001"
  }
}

resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name   = "vpc-flow-log-policy-${local.base_name}-001"
  role   = aws_iam_role.vpc_flow_log.id
  policy = data.aws_iam_policy_document.flow_log_policy.json
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "/aws/vpc/flow-logs/${local.base_name}"

  tags = {
    Name = "cloudwatch-log-group-${local.base_name}-flow-logs-001"
  }
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn

  tags = {
    Name = "flow-log-${local.base_name}-001"
  }
}
resource "aws_vpc" "this" {

  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "vpc-${local.base_name}-001"
  }

  enable_dns_support = true
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "subnet-public-${local.base_name}-001"
  }
}

# We need more than one private subnet for deifining aurora serverless cluster
resource "aws_subnet" "private_1" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.2.0/24"
  tags = {
    Name = "subnet-private-${local.base_name}-001"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.3.0/24"
  tags = {
    Name = "$subnet-private-{local.base_name}-001"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "internet-gateway-${local.base_name}-001"
  }
}

resource "aws_eip" "nat" {
  count  = 1
  domain = "vpc"
  tags = {
    Name = "eip-${local.base_name}-001"
  }
}

resource "aws_nat_gateway" "this" {

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "nat-gateway-${local.base_name}-001"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "route-table-public-${local.base_name}-001"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "route-table-private-${local.base_name}-001"
  }
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# Define Aurora Serverless Cluster
resource "aws_security_group" "aurora" {
  description = "Security group for Aurora Serverless cluster"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "sg-${local.base_name}-aurora-001"
  }

  # TODO
}

# -------------------------------------
# Setting for aurora serverless cluster
# -------------------------------------
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "aurora-cluster-parameter-group-${local.base_name}-001"
  family      = "aurora-postgresql16"
  description = "Aurora cluster parameter group for ${local.base_name}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "rds-cluster-parameter-group-${local.base_name}-001"
  }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "aurora-cluster-${local.base_name}-001"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  database_name      = "difydb"

  master_username             = "dbadmin"
  manage_master_user_password = true

  storage_encrypted = true

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    min_capacity             = 0.0
    max_capacity             = 1.0
    seconds_until_auto_pause = 300 # 5minutes
  }

  tags = {
    Name = "rds-cluster-${local.base_name}-001"
  }
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  tags = {
    Name = "rds-instance-${local.base_name}-001"
  }
}

# ------------------------------------------------
# Settings for Elastic Cache Serverless for Valkey
# ------------------------------------------------

resource "aws_security_group" "valkey" {
  description = "Security group for Valkey Serverless cluster"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "sg-${local.base_name}-valkey-001"
  }

  # TODO
}

resource "aws_elasticache_serverless_cache" "this" {
  engine = "valkey"
  name   = "es-${local.base_name}-001"

  description          = ""
  major_engine_version = "8"

  cache_usage_limits {
    data_storage {
      maximum = "1"
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 1000
    }
  }

  subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  security_group_ids = [aws_security_group.valkey.id]

}

# ------------------------------------------------
# Settings for S3
# ------------------------------------------------
resource "aws_s3_bucket" "dify_data" {
  bucket = "dify-data-${local.base_name}-001"

  tags = {
    Name = "s3-bucket-dify-data-${local.base_name}-001"
  }
}

# Block public access to meets security standards
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
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.region}.s3"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id
  ]

}

# ------------------------------------------------
# Settings for ECS
# ------------------------------------------------

# kms key for ecs logging
resource "aws_kms_key" "ecs_logging" {
  description         = "KMS key for ECS logging"
  enable_key_rotation = true

  tags = {
    Name = "kms-key-${local.base_name}-ecs-logging-001"
  }
}


# cloudwatch log for ECS
resource "aws_cloudwatch_log_group" "ecs" {
  name = "/aws/ecs/${local.base_name}"

  kms_key_id = aws_kms_key.ecs_logging.arn

  tags = {
    Name = "cloudwatch-log-group-${local.base_name}-ecs-001"
  }
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_web" {
  name                 = "${local.base_name}/dify-web"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecs_logging.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_api" {
  name                 = "${local.base_name}/dify-api"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecs_logging.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_worker" {
  name                 = "${local.base_name}/dify-worker"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecs_logging.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_sandbox" {
  name                 = "${local.base_name}/dify-sandbox"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecs_logging.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "ecr_repo_urls" {
  value = {
    web     = aws_ecr_repository.dify_web.repository_url
    api     = aws_ecr_repository.dify_api.repository_url
    worker  = aws_ecr_repository.dify_worker.repository_url
    sandbox = aws_ecr_repository.dify_sandbox.repository_url
  }
}

resource "aws_ecs_cluster" "dify" {
  name = "ecs-cluster-${local.base_name}-001"

  setting {
    name = "containerInsights"

    value = "enabled"
  }

  tags = {
    Name = "ecs-cluster-${local.base_name}-001"
  }
}

# We need tasks for web, api and worker at minimum

# Settings for api task
# iam role settings for api
data "aws_iam_policy_document" "dify_api_task_policy" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = [
      "${aws_cloudwatch_log_group.ecs.arn}:*"
    ]
  }

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

  tags = {
    Name = "dify-api-task-role-${local.base_name}-001"
  }
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
  tags = {
    Name = "sg-${local.base_name}-dify-api-001"
  }
}

resource "aws_ecs_task_definition" "dify_api" {
  family                   = "dify-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

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
      name      = "dify-api"
      image     = "langgenius/dify-api${var.dify_api_version}"
      essential = true

      portMappings = [
        {
          containerPort = 5001
          hostPort      = 5001
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AWS_REGION"
          value = var.region
        },
        {
          name  = "DIFY_DATA_BUCKET"
          value = aws_s3_bucket.dify_data.bucket
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dify-api"
        }
      }
    },
    {
      name      = "dify-sandbox"
      image     = "busybox:latest"
      essential = false
    }
  ])
}

# Settings for worker task
resource "aws_security_group" "dify_worker" {
  description = "Security group for Dify Worker task"
  vpc_id      = aws_vpc.this.id

  # TODO
  tags = {
    Name = "sg-${local.base_name}-dify-worker-001"
  }
}

resource "aws_ecs_task_definition" "dify_worker" {
  family                   = "dify-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

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
        {
          name  = "AWS_REGION"
          value = var.region
        },
        {
          name  = "DIFY_DATA_BUCKET"
          value = aws_s3_bucket.dify_data.bucket
        }
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

# Settings for web  tasks
resource "aws_security_group" "dify_web" {
  description = "Security group for Dify Web task"
  vpc_id      = aws_vpc.this.id

  # TODO
  tags = {
    Name = "sg-${local.base_name}-dify-web-001"
  }
}

resource "aws_ecs_task_definition" "dify_web" {
  family                   = "dify-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

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
      name      = "dify-web"
      image     = "langgenius/dify-web${var.dify_api_version}"
      essential = true

      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AWS_REGION"
          value = var.region
        },
        {
          name  = "DIFY_DATA_BUCKET"
          value = aws_s3_bucket.dify_data.bucket
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
    }
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

  tags = {
    Name = "sg-${local.base_name}-dify-alb-001"
  }
}

resource "aws_alb" "dify_alb" {
  name               = "alb-dify"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.dify_alb.id]
  subnets            = [aws_subnet.public.id]

  enable_deletion_protection = false

  tags = {
    Name = "dify-alb-${local.base_name}-001"
  }
}

resource "aws_lb_target_group" "dify_api" {
  name     = "tg-dify-api"
  port     = 5001
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "dify-api-tg-${local.base_name}-001"
  }
}

resource "aws_lb_target_group" "dify_web" {
  name     = "tg-dify-web"
  port     = 5002
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "dify-worker-tg-${local.base_name}-001"
  }
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

  tags = {
    Name = "dify-web-listener-${local.base_name}-001"
  }
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


  tags = {
    Name = "dify-api-listener-rule-${local.base_name}-001"
  }
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

  tags = {
    Name = "dify-api-listener-rule-${local.base_name}-002"
  }
}


