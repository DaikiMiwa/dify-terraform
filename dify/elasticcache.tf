# ------------------------------------------------
# Settings for ElastiCache for Valkey
# ------------------------------------------------
resource "aws_security_group" "valkey" {
  name        = "${local.base_name}-valkey-001-sg"
  description = "Security group for Valkey cluster with SSL enforcement"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "sg-${local.base_name}-valkey-001"
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

  depends_on = [
    aws_security_group.valkey,
    aws_security_group.dify_api
  ]
}

resource "aws_security_group_rule" "valkey_ingress_6379_worker" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_worker.id
  description              = "Allow inbound traffic from private subnets"

  security_group_id = aws_security_group.valkey.id

  depends_on = [
    aws_security_group.valkey,
    aws_security_group.dify_worker
  ]
}

resource "aws_security_group_rule" "valkey_ingress_6379_plugin_daemon" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_plugin_daemon.id
  description              = "Allow inbound traffic from plugin daemon"

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
  name                    = "${local.base_name}/elasticache/valkey/celery-broker-url-v2"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "celery_broker_url_secret_version" {
  secret_id     = aws_secretsmanager_secret.celery_broker_url_secret.id
  secret_string = "rediss://${aws_elasticache_user.celery_user.user_name}:${urlencode(random_password.celery_valkey_password.result)}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379/1?ssl_cert_reqs=required"

  depends_on = [
    aws_elasticache_replication_group.this,
    aws_elasticache_user.celery_user,
    random_password.celery_valkey_password
  ]

  lifecycle {
    create_before_destroy = true
  }
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

  # 両方のユーザーを同じユーザーグループに含める
  user_ids = [
    aws_elasticache_user.app_user.user_id,
    aws_elasticache_user.celery_user.user_id
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-user-group-${local.base_name}-001"
    }
  )
}

# ElastiCache Parameter Group for Valkey
resource "aws_elasticache_parameter_group" "valkey_ssl" {
  family = "valkey8"
  name   = "${local.base_name}-valkey-params"

  description = "Parameter group for Valkey"

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-parameter-group-${local.base_name}"
    }
  )
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.base_name}-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-subnet-group-${local.base_name}"
    }
  )
}

# ElastiCache Replication Group for Valkey
resource "aws_elasticache_replication_group" "this" {
  description          = "ElastiCache for Valkey - Shared by Dify and Celery"
  replication_group_id = substr("${local.base_name}-valkey", 0, 50)

  engine         = "valkey"
  engine_version = "8.0"
  node_type      = "cache.t3.micro"
  port           = 6379

  num_cache_clusters = 1

  # カスタムパラメータグループを使用
  parameter_group_name = aws_elasticache_parameter_group.valkey_ssl.name

  # Security and networking
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.valkey.id]

  # Auth settings
  user_group_ids = [aws_elasticache_user_group.app_user_group.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  transit_encryption_mode    = "required"

  # Maintenance
  auto_minor_version_upgrade = true

  depends_on = [
    aws_elasticache_subnet_group.this,
    aws_security_group.valkey,
    aws_elasticache_parameter_group.valkey_ssl,
    aws_elasticache_user_group.app_user_group
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-${local.base_name}-001"
    }
  )
}

# ------------------------------------------------
# Celery用のユーザー設定（同じElastiCacheを使用）
# ------------------------------------------------
resource "random_password" "celery_valkey_password" {
  length           = 24
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "celery_valkey_password_secret" {
  name                    = "${local.base_name}/elasticache/valkey/celery-user-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "celery_valkey_password_secret_version" {
  secret_id     = aws_secretsmanager_secret.celery_valkey_password_secret.id
  secret_string = random_password.celery_valkey_password.result
}

resource "aws_elasticache_user" "celery_user" {
  user_id   = "${local.base_name}-celery-id"
  user_name = "celery"
  engine    = "valkey"

  # 論理DB 1番のみアクセス可能に制限
  access_string = "on ~* +@all -@dangerous"

  authentication_mode {
    type      = "password"
    passwords = [random_password.celery_valkey_password.result]
  }

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-user-${local.base_name}-celery-001"
    }
  )
}

