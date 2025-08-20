# ------------------------------------------------
# VPC Endpoints for Dify services
# Note: All VPC endpoints are now managed in the example directory
# This file is kept for future reference but all resources are disabled
# ------------------------------------------------

# Uncomment the sections below if you want to manage VPC endpoints within the dify module
# instead of in the example directory

# ------------------------------------------------
# VPC Endpoints for Dify services
# Note: All VPC endpoints are now managed in the example directory
# This file is kept for future reference but all resources are disabled
# ------------------------------------------------

# All VPC endpoint resources have been moved to example/main.tf
# to avoid conflicts with existing VPC endpoints and to centralize management

# If you want to manage VPC endpoints within the dify module instead,
# uncomment the resources below and set enable_vpc_endpoints = true

/*
# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoint" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${local.base_name}-vpce-001-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-vpce-001"
    }
  )
}

resource "aws_security_group_rule" "vpc_endpoint_ingress_https" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr_block]
  description = "Allow HTTPS traffic within VPC"

  security_group_id = aws_security_group.vpc_endpoint[0].id
}

# S3 VPC Endpoint (Gateway type)
resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids
  policy            = data.aws_iam_policy_document.s3_endpoint_policy[0].json

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-vpce-s3"
    }
  )
}

# ECR VPC Endpoints
resource "aws_vpc_endpoint" "ecr_dkr" {
  count               = var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint[0].id]
  private_dns_enabled = false
  policy              = data.aws_iam_policy_document.ecr_endpoint_policy[0].json

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-vpce-ecr-dkr"
    }
  )
}

resource "aws_vpc_endpoint" "ecr_api" {
  count               = var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint[0].id]
  private_dns_enabled = false
  policy              = data.aws_iam_policy_document.ecr_endpoint_policy[0].json

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-vpce-ecr-api"
    }
  )
}

# CloudWatch Logs VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  count               = var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint[0].id]
  private_dns_enabled = false
  policy              = data.aws_iam_policy_document.logs_endpoint_policy[0].json

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-vpce-logs"
    }
  )
}

# CloudWatch Monitoring VPC Endpoint
resource "aws_vpc_endpoint" "monitoring" {
  count               = var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint[0].id]
  private_dns_enabled = false
  policy              = data.aws_iam_policy_document.monitoring_endpoint_policy[0].json

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-vpce-monitoring"
    }
  )
}

# Bedrock VPC Endpoint
resource "aws_vpc_endpoint" "bedrock" {
  count               = var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.bedrock"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint[0].id]
  private_dns_enabled = false
  policy              = data.aws_iam_policy_document.bedrock_endpoint_policy[0].json

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-vpce-bedrock"
    }
  )
}

# Bedrock Runtime VPC Endpoint
resource "aws_vpc_endpoint" "bedrock_runtime" {
  count               = var.enable_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoint[0].id]
  private_dns_enabled = false
  policy              = data.aws_iam_policy_document.bedrock_runtime_endpoint_policy[0].json

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-vpce-bedrock-runtime"
    }
  )
}

# IAM Policy Documents for VPC Endpoints
data "aws_iam_policy_document" "s3_endpoint_policy" {
  count = var.enable_vpc_endpoints ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "ecr_endpoint_policy" {
  count = var.enable_vpc_endpoints ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "logs_endpoint_policy" {
  count = var.enable_vpc_endpoints ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "monitoring_endpoint_policy" {
  count = var.enable_vpc_endpoints ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:PutDashboard",
      "cloudwatch:GetDashboard",
      "cloudwatch:DeleteDashboard",
      "cloudwatch:ListDashboards",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "bedrock_endpoint_policy" {
  count = var.enable_vpc_endpoints ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
  "bedrock:GetFoundationModel",
  "bedrock:ListFoundationModels",
  "bedrock:GetInferenceProfile",
  "bedrock:ListInferenceProfiles",
      "bedrock:GetModelInvocationLoggingConfiguration",
      "bedrock:PutModelInvocationLoggingConfiguration",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "bedrock_runtime_endpoint_policy" {
  count = var.enable_vpc_endpoints ? 1 : 0
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = ["*"]
  }
}
*/
