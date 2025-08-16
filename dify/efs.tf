resource "aws_security_group" "efs" {
  description = "Allow NFS from ECS tasks"
  vpc_id      = var.vpc_id

  tags = merge(
    var.default_tags,
    {
      Name = "${local.base_name}-sg-efs"
    }
  )
}

resource "aws_security_group_rule" "efs_ingress_from_dify_api" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = aws_security_group.dify_api.id

  description = "Allow NFS traffic from ECS tasks to EFS"
}

resource "aws_security_group_rule" "efs_ingress_from_dify_worker" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = aws_security_group.dify_worker.id

  description = "Allow NFS traffic from ECS tasks to EFS"
}


resource "aws_efs_file_system" "this" {
  creation_token = "${local.base_name}-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(
    var.default_tags,
    {
      Naem = "efs-${local.base_name}-001"
    }
  )
}

# /certs を強制するアクセスポイント（uid/gid は任意。ECS から RO マウント）
resource "aws_efs_access_point" "certs" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = var.efs_root_directory
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(
    var.default_tags,
    {
      Name = "efs-access-point-${local.base_name}-certs-001"
    }
  )
}

# 各サブネットに Mount Target
resource "aws_efs_mount_target" "mt" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
