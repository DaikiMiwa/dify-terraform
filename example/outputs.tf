output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC Endpoint"
  value       = var.create_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}

output "ecr_vpc_endpoint_ids" {
  description = "IDs of the ECR VPC Endpoints"
  value = var.create_vpc_endpoints ? {
    dkr = aws_vpc_endpoint.ecr_dkr[0].id
    api = aws_vpc_endpoint.ecr_api[0].id
  } : {}
}

output "cloudwatch_vpc_endpoint_ids" {
  description = "CloudWatch VPC Endpoint IDs"
  value = var.create_vpc_endpoints ? {
    logs       = aws_vpc_endpoint.logs[0].id
    monitoring = aws_vpc_endpoint.monitoring[0].id
  } : {}
}

output "bedrock_vpc_endpoint_ids" {
  description = "Bedrock VPC Endpoint IDs"
  value = var.create_vpc_endpoints ? {
    bedrock         = aws_vpc_endpoint.bedrock[0].id
    bedrock_runtime = aws_vpc_endpoint.bedrock_runtime[0].id
  } : {}
}

output "secretsmanager_vpc_endpoint_id" {
  description = "Secrets Manager VPC Endpoint ID"
  value       = var.create_vpc_endpoints ? aws_vpc_endpoint.secretsmanager[0].id : null
}

# Output from the Dify module
output "dify_ecr_repos" {
  description = "ECR repository URLs from Dify module"
  value       = module.dify.ecr_repo_urls
}

# Output from the Dify module
output "dify_efs_id" {
  description = "EFS ID from Dify module"
  value       = module.dify.efs_id
}

# ElastiCache outputs from the Dify module
output "dify_elasticache_endpoints" {
  description = "ElastiCache endpoints from Dify module"
  value       = module.dify.elasticache_endpoints
}

output "dify_elasticache_secrets" {
  description = "ElastiCache secrets ARNs from Dify module"
  value       = module.dify.elasticache_secrets
}

# Note: VPC Endpoints are now managed in this file (example/main.tf)
# instead of being managed by the dify module
