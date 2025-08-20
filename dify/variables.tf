variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "ap-northeast-1"
}

variable "vpc_id" {
  description = "The ID of the VPC where resources will be deployed"
  type        = string
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "A list of private subnet IDs where resources will be deployed"
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "A list of public subnet IDs where ALB will be deployed"
  type        = list(string)
  default     = []
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
}

variable "base_name" {
  description = "Base name for resources"
  type        = string
  default     = "dify"
}

variable "aws_rds_cluster_scaling_configuration" {
  description = "Scaling configuration for the RDS cluster"
  type = object({
    min_capacity             = number
    max_capacity             = number
    seconds_until_auto_pause = number
  })

  default = {
    min_capacity             = 0
    max_capacity             = 1
    seconds_until_auto_pause = 300
  }
}

# EFS 上の配置と、コンテナ側のマウント先
variable "efs_root_directory" {
  type    = string
  default = "/certs"
}

variable "efs_ca_filename" {
  type    = string
  default = "rds-ca.pem" # ap-northeast-1-bundle をこのファイル名で置く想定
}

variable "efs_ca_ec" {
  type    = string
  default = "ec-ca.pem" # ap-northeast-1-bundle をこのファイル名で置く想定
}

variable "container_cert_mount_path" {
  type    = string
  default = "/etc/ssl/dify-certs"
}

variable "route_table_ids" {
  description = "A list of route table IDs for Gateway VPC endpoints"
  type        = list(string)
  default     = []
}

variable "enable_vpc_endpoints" {
  description = "Whether to enable VPC endpoints for AWS services. Set to false to use NAT Gateway instead."
  type        = bool
  default     = false
}

variable "alb_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB. Use ['0.0.0.0/0'] for public access or VPC CIDR for internal access only."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

