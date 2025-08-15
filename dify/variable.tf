variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "ap-northeast-1"
}

variable "dify_api_version" {
  description = "The version of the Dify API to use"
  type        = string
  default     = "0.7.3"
}

variable "vpc_id" {
  description = "The ID of the VPC where resources will be deployed"
  type        = string
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "public_subnet_id" {
  description = "The ID of the public subnet where resources will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "A list of private subnet IDs where resources will be deployed"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets where the Aurora cluster will be deployed"
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

variable "aurora_cluster_scaling_configuration" {
  description = "Configuration for RDS cluster scaling"
  type = object({
    max_capacity             = number
    min_capacity             = number
    seconds_until_auto_pause = number
  })
  default = {
    max_capacity             = 0.0
    min_capacity             = 1.0
    seconds_until_auto_pause = 300 # minutes
  }
}

