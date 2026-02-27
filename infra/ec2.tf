# Security group: with CloudFront we allow only port 80 from CloudFront IPs;
# without CloudFront we allow port 7860 from allow_http_cidr.
resource "aws_security_group" "app" {
  name_prefix = "${var.app_name}-"
  description = "Career chatbot Gradio app"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = local.use_cloudfront ? [1] : []
    content {
      description     = "HTTP from CloudFront only"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
    }
  }

  dynamic "ingress" {
    for_each = local.use_cloudfront ? [] : [1]
    content {
      description = "Gradio UI"
      from_port   = 7860
      to_port     = 7860
      protocol    = "tcp"
      cidr_blocks = [var.allow_http_cidr]
    }
  }

  dynamic "ingress" {
    for_each = var.ssh_cidr != "" ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { App = var.app_name }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# User data: install deps, clone repo, sync S3 context, run app via systemd.
# When use_cloudfront=true we install Caddy (port 80 → 127.0.0.1:7860) and bind Gradio to localhost.
locals {
  user_data = templatefile("${path.module}/user_data.sh", {
    app_name             = var.app_name
    app_dir              = local.app_dir
    context_bucket       = aws_s3_bucket.context.id
    context_prefix       = var.context_prefix
    app_s3_uri           = var.app_s3_uri
    git_repo_url         = var.git_repo_url
    git_branch           = var.git_branch
    aws_region           = var.region
    ssm_openai_param     = local.ssm_openai_param
    ssm_pushover_token   = var.pushover_token != "" ? local.ssm_pushover_token : ""
    ssm_pushover_user    = var.pushover_user != "" ? local.ssm_pushover_user : ""
    use_cloudfront       = local.use_cloudfront
    app_domain           = var.app_domain
  })
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.user_data
  associate_public_ip_address = true

  lifecycle {
    precondition {
      condition     = var.app_s3_uri != "" || var.git_repo_url != ""
      error_message = "Set either app_s3_uri (deploy from local/S3) or git_repo_url (clone from Git)."
    }
  }

  # ARM (t4g) uses AL2023 ARM AMI (snapshot requires >= 30 GB)
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = var.app_name
    App  = var.app_name
  }
}

# Elastic IP so the instance keeps a stable public IP across restarts; CloudFront origin (public_dns) continues to resolve to this IP.
# Use var.eip_allocation_id to attach an existing EIP (e.g. 54.219.225.202); otherwise Terraform creates a new one.
resource "aws_eip" "app" {
  count    = var.eip_allocation_id == "" ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.app.id
  tags     = { App = var.app_name }
}

resource "aws_eip_association" "app" {
  count         = var.eip_allocation_id != "" ? 1 : 0
  allocation_id = var.eip_allocation_id
  instance_id   = aws_instance.app.id
}

locals {
  app_public_ip = var.eip_allocation_id != "" ? data.aws_eip.existing[0].public_ip : aws_eip.app[0].public_ip
}

data "aws_eip" "existing" {
  count  = var.eip_allocation_id != "" ? 1 : 0
  id     = var.eip_allocation_id
}
