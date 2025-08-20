# ------------------------------------------------
# Settings for Application Load balancer for ecs
# ------------------------------------------------
resource "aws_security_group" "dify_alb" {
  name        = "${local.base_name}-alb-001-sg"
  description = "Security group for Dify ALB"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-alb-001"
    }
  )
}

# ALB inbound rules
resource "aws_security_group_rule" "dify_alb_ingress_80" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Allow inbound traffic on port 80 from VPC CIDR block"

  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_security_group_rule" "dify_alb_ingress_443" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_security_group_rule" "dify_alb_egress_plugin_daemon" {
  type                     = "egress"
  from_port                = 5002
  to_port                  = 5002
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_plugin_daemon.id
  description              = "Allow outbound traffic to plugin daemon tasks"

  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_security_group_rule" "dify_alb_egress_plugin_install" {
  type                     = "egress"
  from_port                = 5003
  to_port                  = 5003
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_plugin_daemon.id
  description              = "Allow outbound traffic to plugin installation service"

  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_security_group_rule" "dify_alb_egress_sandbox" {
  type                     = "egress"
  from_port                = 8194
  to_port                  = 8194
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_sandbox.id
  description              = "Allow outbound traffic to sandbox tasks"

  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_alb" "dify_alb" {
  name               = "alb-${local.base_name}-dify-001"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.dify_alb.id
  ]
  subnets = var.public_subnet_ids

  enable_deletion_protection = false

  depends_on = [
    aws_security_group.dify_alb
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "alb-${local.base_name}-dify-001"
    }
  )
}

# TODO: Need review
resource "aws_lb_target_group" "dify_api" {
  name        = "tg-${local.base_name}-dify-api"
  port        = 5001
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    timeout             = 20
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "tg-${local.base_name}-dify-api-001"
    }
  )
}

resource "aws_lb_target_group" "dify_web" {
  name        = "tg-${local.base_name}-dify-web"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200,307"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "tg-${local.base_name}-dify-web-001"
    }
  )
}

resource "aws_lb_target_group" "dify_plugin_daemon" {
  name        = "tg-${local.base_name}-dify-plugin"
  port        = 5002
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health/check"
    timeout             = 20
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "tg-${local.base_name}-dify-plugin-001"
    }
  )
}

resource "aws_lb_target_group" "dify_sandbox" {
  name        = "tg-${local.base_name}-dify-sandbox"
  port        = 8194
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 60
    matcher             = "200"
    path                = "/health"
    timeout             = 10
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "tg-${local.base_name}-dify-sandbox-001"
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

  depends_on = [
    aws_lb_target_group.dify_web,
    aws_lb_target_group.dify_api,
    aws_lb_target_group.dify_plugin_daemon,
    aws_lb_target_group.dify_sandbox,
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "alb-listener-${local.base_name}-dify-001"
    }
  )
}

# Use path base routing to forward requests to the api target group
locals {
  api_paths_basic = ["/console/api", "/api", "/files"]
  api_paths_v1 = ["/v1/apps", "/v1/workflows", "/v1/datasets", "/v1/chat-messages", "/v1/completion-messages"]
}

resource "aws_lb_listener_rule" "dify_api_basic" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = local.api_paths_basic
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_api.arn
  }

  depends_on = [
    aws_lb_target_group.dify_api,
    aws_lb_listener.https
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "dify-api-basic-listener-rule-${local.base_name}-001"
    }
  )
}

resource "aws_lb_listener_rule" "dify_api_v1" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 14

  condition {
    path_pattern {
      values = local.api_paths_v1
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_api.arn
  }

  depends_on = [
    aws_lb_target_group.dify_api,
    aws_lb_listener.https
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "dify-api-v1-listener-rule-${local.base_name}-001"
    }
  )
}

resource "aws_lb_listener_rule" "dify_api_basic_routing" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 16

  condition {
    path_pattern {
      values = [for path in local.api_paths_basic : "${path}/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_api.arn
  }

  depends_on = [
    aws_lb_target_group.dify_api,
    aws_lb_listener.https
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "dify-api-basic-routing-listener-rule-${local.base_name}-001"
    }
  )
}

resource "aws_lb_listener_rule" "dify_api_v1_routing" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 17

  condition {
    path_pattern {
      values = [for path in local.api_paths_v1 : "${path}/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_api.arn
  }

  depends_on = [
    aws_lb_target_group.dify_api,
    aws_lb_listener.https
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "dify-api-v1-routing-listener-rule-${local.base_name}-001"
    }
  )
}

# Plugin daemon routing for /plugin path
resource "aws_lb_listener_rule" "dify_plugin_daemon" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 30

  condition {
    path_pattern {
      values = ["/plugin", "/plugin/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_plugin_daemon.arn
  }

  depends_on = [
    aws_lb_target_group.dify_plugin_daemon,
    aws_lb_listener.https
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "dify-plugin-daemon-listener-rule-${local.base_name}-001"
    }
  )
}

# Sandbox routing for /sandbox and /v1/sandbox paths  
resource "aws_lb_listener_rule" "dify_sandbox" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 18

  condition {
    path_pattern {
      values = ["/sandbox", "/sandbox/*", "/v1/sandbox", "/v1/sandbox/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_sandbox.arn
  }

  depends_on = [
    aws_lb_target_group.dify_sandbox,
    aws_lb_listener.https
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "dify-sandbox-listener-rule-${local.base_name}-001"
    }
  )
}
