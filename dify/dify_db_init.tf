# -----------------------------------------------
# DB認証情報をEFSに保存するタスク定義
# -----------------------------------------------

resource "aws_security_group" "dify_db_init" {
  name        = "${local.base_name}-db-init-001-sg"
  description = "Security group for Dify DB Init task"
  vpc_id      = var.vpc_id

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-db-init-001"
    }
  )
}

# DB Init egress rules
resource "aws_security_group_rule" "dify_db_init_egress_efs" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.dify_db_init.id
  source_security_group_id = aws_security_group.efs.id

  description = "Allow NFS traffic from ECS tasks to EFS"
}

# VPC Endpoints への HTTPS 通信を許可
resource "aws_security_group_rule" "dify_db_init_egress_vpc_endpoints" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_db_init.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTPS to VPC endpoints for CloudWatch Logs, ECR, Secrets Manager"
}

# VPC Endpoints への HTTP 通信を許可（ECR等で必要）
resource "aws_security_group_rule" "dify_db_init_egress_vpc_endpoints_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_db_init.id
  cidr_blocks       = [var.vpc_cidr_block]
  description       = "Allow HTTP to VPC endpoints for ECR"
}

# インターネットへの HTTPS 通信を許可（CA証明書ダウンロード用）
resource "aws_security_group_rule" "dify_db_init_egress_internet_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.dify_db_init.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS to internet for downloading RDS CA certificate"
}


resource "aws_ecs_task_definition" "dify_db_init" {
  family                   = "dify-db-init"
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


  container_definitions = jsonencode([
    {
      name      = "dify-db-init"
      image     = "public.ecr.aws/amazonlinux/amazonlinux:2023"
      essential = true


      mountPoints = [
        {
          sourceVolume  = "efs-certs"
          containerPath = var.container_cert_mount_path
          readOnly      = false
        }
      ]

      command = [
        "/bin/sh",
        "-c",
        <<-EOF
        set -e
        
        echo "Starting RDS CA certificate download task..."
        
        # Install wget if not available
        yum update -y && yum install -y wget
        
        # Create cert directory
        mkdir -p "${var.container_cert_mount_path}"
        
        # Download RDS CA certificate if not exists
        if [ ! -f "${var.container_cert_mount_path}/${var.efs_ca_filename}" ]; then
          echo "Downloading RDS CA certificate..."
          wget https://truststore.pki.rds.amazonaws.com/ap-northeast-1/ap-northeast-1-bundle.pem -O "${var.container_cert_mount_path}/${var.efs_ca_filename}"
          chmod 644 "${var.container_cert_mount_path}/${var.efs_ca_filename}"
          echo "RDS CA certificate downloaded and saved to ${var.container_cert_mount_path}/${var.efs_ca_filename}"
        else
          echo "RDS CA certificate already exists at ${var.container_cert_mount_path}/${var.efs_ca_filename}"
        fi
        
        echo "Certificate setup task completed successfully!"
        EOF
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "dify-db-init"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])

  tags = merge(
    var.default_tags,
    {
      Name = "ecs-task-definition-${local.base_name}-dify-db-init-001"
    }
  )
}

# Note: ECS Service removed to prevent continuous execution
# To run the certificate download task manually, use:
# aws ecs run-task --cluster ecs-cluster-dify-test-001-001 --task-definition dify-db-init --launch-type FARGATE \
#   --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxx,subnet-yyy],securityGroups=[sg-xxx],assignPublicIp=DISABLED}'

