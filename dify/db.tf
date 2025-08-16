# -------------------------------------
# Setting for aurora serverless cluster
# -------------------------------------
resource "aws_security_group" "aurora" {
  description = "Security group for Aurora Serverless cluster"
  vpc_id      = var.vpc_id

  # ルールはここに書かない（ingress/egress ブロックを空にしておく）

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-sg-aurora"
    }
  )
}

# Aurora ingress rules
resource "aws_security_group_rule" "aurora_ingress_api" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_api.id

  security_group_id = aws_security_group.aurora.id
}

resource "aws_security_group_rule" "aurora_ingress_worker" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dify_worker.id

  security_group_id = aws_security_group.aurora.id
}

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "aurora-cluster-parameter-group-${local.base_name}-001"
  family      = "aurora-postgresql16"
  description = "Aurora cluster parameter group for ${local.base_name}"

  # Enforce ssl connection to meets secrurity requirements in ACN
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = merge(
    var.default_tags,
    {
      Name = "rds-cluster-parameter-group-${local.base_name}-001"
    }
  )
}

resource "aws_db_subnet_group" "aurora" {
  name       = "aurora-subnet-group-${local.base_name}-001"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.default_tags,
    {
      Name = "rds-subnet-group-${local.base_name}-001"
    }
  )
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier   = "aurora-cluster-${local.base_name}-001"
  engine               = "aurora-postgresql"
  engine_mode          = "provisioned"
  database_name        = "dify"
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  master_username             = "dbadmin"
  manage_master_user_password = true

  storage_encrypted = true
  vpc_security_group_ids = [aws_security_group.aurora.id]


  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    max_capacity             = var.aws_rds_cluster_scaling_configuration.max_capacity
    min_capacity             = var.aws_rds_cluster_scaling_configuration.min_capacity
    seconds_until_auto_pause = var.aws_rds_cluster_scaling_configuration.seconds_until_auto_pause
  }

  tags = merge(
    var.default_tags,
    {
      Name = "rds-cluster-${local.base_name}-001"
    }
  )
}

resource "aws_rds_cluster_instance" "aurora_instance" {

  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  performance_insights_enabled = true

  tags = merge(
    var.default_tags,
    {
      Name = "rds-cluster-instance-${local.base_name}-001"
    }
  )
}

