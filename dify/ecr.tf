# ------------------------------------------------
# Settings for ECR
# ------------------------------------------------
# private ecr for dify containers 
resource "aws_ecr_repository" "dify_web" {
  name                 = "${local.base_name}/dify-web"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecr-repo-${local.base_name}-dify-web-001"
    }
  )
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_api" {
  name                 = "${local.base_name}/dify-api"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecr-repo-${local.base_name}-dify-api-001"
    }
  )
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_sandbox" {
  name                 = "${local.base_name}/dify-sandbox"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecr-repo-${local.base_name}-dify-sandbox-001"
    }
  )
}

# private ecr for dify containers 
resource "aws_ecr_repository" "dify_plugin_daemon" {
  name                 = "${local.base_name}/dify-plugin_daemon"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "ecr-repo-${local.base_name}-dify-plugin-daemon-001"
    }
  )
}

