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
