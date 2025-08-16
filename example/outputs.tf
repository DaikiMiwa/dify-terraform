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
  value       = aws_vpc_endpoint.s3.id
}

output "ecr_vpc_endpoint_ids" {
  description = "IDs of the ECR VPC Endpoints"
  value = {
    dkr = aws_vpc_endpoint.ecr_dkr.id
    api = aws_vpc_endpoint.ecr_api.id
  }
}

# Output from the Dify module
output "dify_ecr_repos" {
  description = "ECR repository URLs from Dify module"
  value       = module.dify.ecr_repo_urls
}
