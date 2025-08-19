locals {
  base_name = "dify-test-001"

  default_tags = {
    Project     = "dify"
    Environment = "test"
    IaC         = "terraform"
    airid       = "test-airid"
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpc-${local.base_name}-001"
    }
  )
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    local.default_tags,
    {
      Name = "igw-${local.base_name}-001"
    }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    local.default_tags,
    {
      Name = "eip-${local.base_name}-nat-001"
    }
  )
}

# Public Subnets
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.default_tags,
    {
      Name = "subnet-${local.base_name}-public-00${count.index + 1}"
      Type = "Public"
    }
  )
}

# Private Subnets
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(
    local.default_tags,
    {
      Name = "subnet-${local.base_name}-private-00${count.index + 1}"
      Type = "Private"
    }
  )
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(
    local.default_tags,
    {
      Name = "natgw-${local.base_name}-001"
    }
  )
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    local.default_tags,
    {
      Name = "rt-${local.base_name}-public-001"
    }
  )
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(
    local.default_tags,
    {
      Name = "rt-${local.base_name}-private-001"
    }
  )
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# S3 VPC Endpoint - Conditional creation to avoid conflicts
resource "aws_vpc_endpoint" "s3" {
  count             = var.create_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id, aws_route_table.public.id]

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-s3-001"
    }
  )
}

# ECR VPC Endpoints - Conditional creation to avoid DNS conflicts
resource "aws_vpc_endpoint" "ecr_dkr" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-ecr-dkr-001"
    }
  )
}

resource "aws_vpc_endpoint" "ecr_api" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-ecr-api-001"
    }
  )
}

# CloudWatch Logs VPC Endpoint
resource "aws_vpc_endpoint" "logs" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-logs-001"
    }
  )
}

# CloudWatch Monitoring VPC Endpoint
resource "aws_vpc_endpoint" "monitoring" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-monitoring-001"
    }
  )
}

# Bedrock VPC Endpoint
resource "aws_vpc_endpoint" "bedrock" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.bedrock"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-bedrock-001"
    }
  )
}

# Bedrock Runtime VPC Endpoint
resource "aws_vpc_endpoint" "bedrock_runtime" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-bedrock-runtime-001"
    }
  )
}

# Secrets Manager VPC Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-secretsmanager-001"
    }
  )
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoint" {
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
    description = "Allow HTTPS traffic within VPC"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
    description = "Allow HTTP traffic within VPC"
  }

  tags = merge(
    local.default_tags,
    {
      Name = "sg-${local.base_name}-vpce-001"
    }
  )
}

# Security Group for EC2 Instance Connect Endpoint
resource "aws_security_group" "instance_connect_endpoint" {
  name        = "${local.base_name}-ice-001"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.main.id

  # Allow SSH traffic from anywhere (Instance Connect will handle authentication)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH traffic through Instance Connect"
  }

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
    description = "Allow SSH traffic to EC2 instances in VPC"
  }

  tags = merge(
    local.default_tags,
    {
      Name = "sg-${local.base_name}-ice-001"
    }
  )
}


# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}


# SSM (Parameter Store) VPC Endpoint
resource "aws_vpc_endpoint" "ssm" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-ssm-001"
    }
  )
}

# SSMMessages VPC Endpoint (ECS Exec)
resource "aws_vpc_endpoint" "ssmmessages" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-ssmmessages-001"
    }
  )
}

# EC2Messages VPC Endpoint (ECS Exec)
resource "aws_vpc_endpoint" "ec2messages" {
  count               = var.create_vpc_endpoints ? 1 : 0
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(
    local.default_tags,
    {
      Name = "vpce-${local.base_name}-ec2messages-001"
    }
  )
}

# EC2 Instance Connect Endpoint
resource "aws_ec2_instance_connect_endpoint" "main" {
  count              = var.create_vpc_endpoints ? 1 : 0
  subnet_id          = aws_subnet.private[0].id
  security_group_ids = [aws_security_group.instance_connect_endpoint.id]

  tags = merge(
    local.default_tags,
    {
      Name = "ice-${local.base_name}-001"
    }
  )
}

# Call the Dify module
module "dify" {
  source = "../dify"

  region             = var.region
  vpc_id             = aws_vpc.main.id
  vpc_cidr_block     = aws_vpc.main.cidr_block
  private_subnet_ids = aws_subnet.private[*].id
  public_subnet_ids  = aws_subnet.public[*].id
  route_table_ids    = [aws_route_table.private.id, aws_route_table.public.id]

  # Disable VPC endpoints in the dify module since they're created here
  enable_vpc_endpoints = false

  default_tags = local.default_tags

  base_name = local.base_name
}
