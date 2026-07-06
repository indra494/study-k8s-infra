provider "aws" {
  region = "ap-northeast-2" # 서울 리전
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}