# AWS Region
region = "ap-northeast-1"

# Network Configuration
vpc_cidr_block       = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# VPC Endpoints
# Set to true to create VPC endpoints, false if they already exist to avoid conflicts
create_vpc_endpoints = true
