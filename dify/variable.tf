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
  type = map(object({
    Project     = string
    Environment = string
    IaC         = string
    airid       = string
  }))
}

variable "base_name" {
  description = "Base name for resources"
  type        = string
  default     = "dify"
}

variable "aws_rds_cluster_scaling_configuration" {
  description = "Scaling configuration for the RDS cluster"
  type        = object({
    min_capacity = number
    max_capacity = number
    seconds_until_auto_pause = number
  })

  default = {
    min_capacity              = 0
    max_capacity              = 1
    seconds_until_auto_pause  = 300
  }
}