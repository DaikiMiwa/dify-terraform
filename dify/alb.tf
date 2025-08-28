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
  cidr_blocks = var.alb_ingress_cidr_blocks
  description = "Allow inbound traffic on port 80"

  security_group_id = aws_security_group.dify_alb.id
}

resource "aws_security_group_rule" "dify_alb_ingress_443" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = var.alb_ingress_cidr_blocks
  description = "Allow inbound traffic on port 443"

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




# HTTPSアウトバウンドルール（Cognito認証用）
resource "aws_security_group_rule" "dify_alb_egress_https" {
  type        = "egress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Allow outbound traffic on port 443"

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



# HTTPからHTTPSへのリダイレクト用リスナー
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_alb.dify_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(
    var.default_tags,
    {
      Name = "alb-listener-http-redirect-${local.base_name}-dify-001"
    }
  )
}

# HTTPSリスナー（Cognito認証付き）
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_alb.dify_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.create_acm_certificate ? aws_acm_certificate_validation.dify_cert_validation[0].certificate_arn : null

  default_action {
    order = 1
    type  = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.dify.arn
      user_pool_client_id = aws_cognito_user_pool_client.dify.id
      user_pool_domain    = aws_cognito_user_pool_domain.dify.domain
      session_cookie_name = "AWSELBAuthSessionCookie"
      scope               = "openid"
      session_timeout     = 3600
      on_unauthenticated_request = "authenticate"
    }
  }

  default_action {
    order = 2
    type  = "forward"
    target_group_arn = aws_lb_target_group.dify_web.arn
  }

  depends_on = [
    aws_lb_target_group.dify_web,
    aws_lb_target_group.dify_api,
    aws_cognito_user_pool.dify,
    aws_cognito_user_pool_client.dify,
    aws_cognito_user_pool_domain.dify
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "alb-listener-https-${local.base_name}-dify-001"
    }
  )
}

# Use path base routing to forward requests to the api target group
locals {
  api_paths_basic = ["/console/api", "/api", "/files"]
  api_paths_v1    = ["/v1/apps", "/v1/workflows", "/v1/datasets", "/v1/chat-messages", "/v1/completion-messages"]
}

# OAuth2パスは認証をスキップする必要がある
resource "aws_lb_listener_rule" "oauth2_paths" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 5

  condition {
    path_pattern {
      values = ["/oauth2/*"]
    }
  }

  # OAuth2パスは認証なしでWebターゲットに直接転送
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dify_web.arn
  }

  depends_on = [
    aws_lb_target_group.dify_web,
    aws_lb_listener.https
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "oauth2-listener-rule-${local.base_name}-001"
    }
  )
}

resource "aws_lb_listener_rule" "dify_api_basic" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = local.api_paths_basic
    }
  }

  # Cognito認証を追加
  action {
    order = 1
    type  = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.dify.arn
      user_pool_client_id = aws_cognito_user_pool_client.dify.id
      user_pool_domain    = aws_cognito_user_pool_domain.dify.domain
      session_cookie_name = "AWSELBAuthSessionCookie"
      scope               = "openid"
      session_timeout     = 3600
      on_unauthenticated_request = "authenticate"
    }
  }

  action {
    order = 2
    type  = "forward"
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

  # Cognito認証を追加
  action {
    order = 1
    type  = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.dify.arn
      user_pool_client_id = aws_cognito_user_pool_client.dify.id
      user_pool_domain    = aws_cognito_user_pool_domain.dify.domain
      session_cookie_name = "AWSELBAuthSessionCookie"
      scope               = "openid"
      session_timeout     = 3600
      on_unauthenticated_request = "authenticate"
    }
  }

  action {
    order = 2
    type  = "forward"
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

  # Cognito認証を追加
  action {
    order = 1
    type  = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.dify.arn
      user_pool_client_id = aws_cognito_user_pool_client.dify.id
      user_pool_domain    = aws_cognito_user_pool_domain.dify.domain
      session_cookie_name = "AWSELBAuthSessionCookie"
      scope               = "openid"
      session_timeout     = 3600
      on_unauthenticated_request = "authenticate"
    }
  }

  action {
    order = 2
    type  = "forward"
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

  # Cognito認証を追加
  action {
    order = 1
    type  = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.dify.arn
      user_pool_client_id = aws_cognito_user_pool_client.dify.id
      user_pool_domain    = aws_cognito_user_pool_domain.dify.domain
      session_cookie_name = "AWSELBAuthSessionCookie"
      scope               = "openid"
      session_timeout     = 3600
      on_unauthenticated_request = "authenticate"
    }
  }

  action {
    order = 2
    type  = "forward"
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


