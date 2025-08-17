# ------------------------------------------------
# Settings for Elastic Cache Serverless for Valkey
# ------------------------------------------------
resource "aws_security_group" "valkey" {
  description = "Security group for Valkey Serverless cluster"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-sg-valkey"
    }
  )
}

# Valkey ingress rules for port 6379
resource "aws_security_group_rule" "valkey_ingress_6379_api" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_api.id
  description              = "Allow inbound traffic from private subnets"

  security_group_id = aws_security_group.valkey.id
}

resource "aws_security_group_rule" "valkey_ingress_6379_worker" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_worker.id
  description              = "Allow inbound traffic from private subnets"

  security_group_id = aws_security_group.valkey.id
}

# Valkey ingress rules for port 6380
resource "aws_security_group_rule" "valkey_ingress_6380_api" {
  type                     = "ingress"
  from_port                = 6380
  to_port                  = 6380
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_api.id
  description              = "Allow inbound traffic from ECS tasks"

  security_group_id = aws_security_group.valkey.id
}

resource "aws_security_group_rule" "valkey_ingress_6380_worker" {
  type                     = "ingress"
  from_port                = 6380
  to_port                  = 6380
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_worker.id
  description              = "Allow inbound traffic from ECS tasks"

  security_group_id = aws_security_group.valkey.id
}

# settings for valkey user for dify
resource "random_password" "valkey_password" {
  length           = 24
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "valkey_password_secret" {
  name                    = "${local.base_name}/elasticache/valkey/app-user-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "valkey_password_secret_version" {
  secret_id     = aws_secretsmanager_secret.valkey_password_secret.id
  secret_string = random_password.valkey_password.result
}

resource "aws_secretsmanager_secret" "celery_broker_url_secret" {
  name                    = "${local.base_name}/elasticache/valkey/celery-broker-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "celery_broker_url_secret_version" {
  secret_id     = aws_secretsmanager_secret.celery_broker_url_secret.id
  secret_string = "redis://${aws_elasticache_user.app_user.user_name}:${random_password.valkey_password.result}@${aws_elasticache_serverless_cache.this.endpoint[0].address}:6379/1"

  depends_on = [
    aws_elasticache_serverless_cache.this,
    aws_elasticache_user.app_user,
    random_password.valkey_password
  ]
}

resource "aws_elasticache_user" "app_user" {
  user_id   = "${local.base_name}-dify-id"
  user_name = "dify"
  engine    = "valkey" # もしエラーになる古いProviderなら "redis" を一時的に使用

  # 例: すべてのキーに対して危険コマンド以外を許可
  access_string = "on ~* +@all -@dangerous"

  authentication_mode {
    type      = "password"
    passwords = [random_password.valkey_password.result]
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
  user_group_id = "${local.base_name}-dify-user-group"
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

