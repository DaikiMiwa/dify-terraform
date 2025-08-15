# ------------------------------------------------
# Settings for Application Load balancer for ecs
# ------------------------------------------------
resource "aws_security_group" "dify_alb" {
  description = "Security group for Dify ALB"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-dify-alb-001"
    }
  )
}

# ALB inbound rules
resource "aws_security_group_rule" "dify_alb_ingress_80" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr_block]
  description = "Allow inbound traffic on port 80 from VPC CIDR block"
  
  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_security_group_rule" "dify_alb_ingress_443" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr_block]
  description = "Allow inbound traffic on port 443 from VPC CIDR block"
  
  security_group_id = aws_security_group.dify_alb.id
}

# ALB outbound rules
resource "aws_security_group_rule" "dify_alb_egress_web" {
  type                     = "egress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_web.id
  description              = "Allow outbound traffic to web tasks"
  
  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_security_group_rule" "dify_alb_egress_api" {
  type                     = "egress"
  from_port                = 5001
  to_port                  = 5001
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_api.id
  description              = "Allow outbound traffic to api tasks"
  
  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_alb" "dify_alb" {
  name               = "alb-dify"
  internal           = true
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.dify_alb.id
  ]
  subnets = var.public_subnet_ids

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
  vpc_id   = var.vpc_id

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
  vpc_id   = var.vpc_id

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
