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


# Password for default user
resource "random_password" "valkey_default_password" {
  length           = 24
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "valkey_default_password_secret" {
  name                    = "${local.base_name}/elasticache/valkey/default-user-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "valkey_default_password_secret_version" {
  secret_id     = aws_secretsmanager_secret.valkey_default_password_secret.id
  secret_string = random_password.valkey_default_password.result
}

# App user password no longer needed - using single auth_token

resource "aws_secretsmanager_secret" "celery_broker_url_secret" {
  name                    = "${local.base_name}/elasticache/valkey/celery-broker-url-v2"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "celery_broker_url_secret_version" {
  secret_id     = aws_secretsmanager_secret.celery_broker_url_secret.id
  secret_string = "rediss://:${urlencode(random_password.valkey_default_password.result)}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379/1?ssl_cert_reqs=required"

  depends_on = [
    aws_elasticache_replication_group.this,
    random_password.valkey_default_password
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# No individual users needed - using auth_token for simple AUTH

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

  # Auth settings with simple password
  auth_token                   = random_password.valkey_default_password.result
  auth_token_update_strategy   = "ROTATE"
  
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  transit_encryption_mode    = "required"

  # Maintenance
  auto_minor_version_upgrade = true

  depends_on = [
    aws_elasticache_subnet_group.this,
    aws_security_group.valkey,
    aws_elasticache_parameter_group.valkey_ssl
  ]

  tags = merge(
    var.default_tags,
    {
      Name = "elasticache-${local.base_name}-001"
    }
  )
}

# Celery now uses the same auth_token as other services

