terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# CloudFront requires ACM certificates to be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-arm64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  app_dir = "/opt/${var.app_name}"
  # SSM parameter names (must match what app.py expects via env)
  ssm_openai_param   = "/${var.app_name}/openai-api-key"
  ssm_pushover_token = "/${var.app_name}/pushover-token"
  ssm_pushover_user  = "/${var.app_name}/pushover-user"
  # When app_domain and hosted_zone_id are set, we use CloudFront + HTTPS.
  # Cert is supplied via acm_certificate_arn (create and validate it in ACM us-east-1 yourself).
  use_cloudfront = var.app_domain != "" && var.hosted_zone_id != ""
}

# AWS-managed prefix list for CloudFront origin-facing IPs (used to restrict EC2 so only CloudFront can reach the origin).
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = local.use_cloudfront ? 1 : 0
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.global.cloudfront.origin-facing"]
  }
}
