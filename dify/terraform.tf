terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.2.0"
    }
    random = {
      source  = "hashicorp/random"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}