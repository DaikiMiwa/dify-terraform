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
      "ecr:BatchGetImage"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = [
      aws_cloudwatch_log_group.ecs.arn,
      "${aws_cloudwatch_log_group.ecs.arn}:*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      "arn:aws:secretsmanager:*:*:secret:ecs/dify/*",
      "arn:aws:secretsmanager:*:*:secret:elasticache/valkey/*",
      "arn:aws:secretsmanager:*:*:secret:rds!cluster-*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter"
    ]

    resources = [
      "arn:aws:ssm:*:*:parameter/dify/*",
      "arn:aws:ssm:*:*:parameter/dify"
    ]
  }
}

resource "aws_iam_role" "dify_task_execution_role" {
  name               = "dify-task-execution-role-${local.base_name}-001"
  assume_role_policy = data.aws_iam_policy_document.dify_task_execution_assume_role.json
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
data "aws_iam_policy_document" "dify_api_task_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
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
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]

    resources = [
      "arn:aws:bedrock:*::foundation-model/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      "arn:aws:secretsmanager:*:*:secret:ecs/dify/*",
      "arn:aws:secretsmanager:*:*:secret:elasticache/valkey/*",
      "arn:aws:secretsmanager:*:*:secret:rds!cluster-*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter"
    ]

    resources = [
      "arn:aws:ssm:*:*:parameter/dify/*",
      "arn:aws:ssm:*:*:parameter/dify"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]

    resources = ["*"]
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
  assume_role_policy = data.aws_iam_policy_document.dify_api_task_assume_role.json

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

# Web task role - minimal permissions for frontend
data "aws_iam_policy_document" "dify_web_task_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "dify_web_task_policy" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      "arn:aws:secretsmanager:*:*:secret:ecs/dify/*",
      "arn:aws:secretsmanager:*:*:secret:elasticache/valkey/*",
      "arn:aws:secretsmanager:*:*:secret:rds!cluster-*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter"
    ]

    resources = [
      "arn:aws:ssm:*:*:parameter/dify/*",
      "arn:aws:ssm:*:*:parameter/dify"
    ]
  }
}

resource "aws_iam_role" "dify_web_task_role" {
  name               = "dify-web-task-role-${local.base_name}-001"
  assume_role_policy = data.aws_iam_policy_document.dify_web_task_assume_role.json

  tags = merge(
    var.default_tags,
    {
      Name = "iam-role-${local.base_name}-dify-web-task-001"
    }
  )
}

resource "aws_iam_role_policy" "dify_web_task_policy" {
  name   = "dify-web-task-policy-${local.base_name}-001"
  role   = aws_iam_role.dify_web_task_role.id
  policy = data.aws_iam_policy_document.dify_web_task_policy.json
}
