variable "region" {
  type    = string
  default = "us-west-1"
}

variable "app_name" {
  type    = string
  default = "career-chatbot"
}

variable "app_domain" {
  type        = string
  default     = ""
  description = "Public domain name (e.g. chat.example.com). Leave empty to use instance public IP only."
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = "Route53 hosted zone id for your domain (required for CloudFront + HTTPS)."
}

variable "manage_app_dns_record" {
  type        = bool
  default     = true
  description = "If true, Terraform creates the Route53 A/alias record for app_domain. Set to false if you already created that record manually (e.g. chat.example.com)."
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN in us-east-1 for app_domain. Required when using CloudFront: create the cert in ACM (us-east-1), validate via DNS, then set this (e.g. arn:aws:acm:us-east-1:...)."
}

variable "openai_api_key" {
  type        = string
  sensitive   = true
  description = "OpenAI API key; stored in SSM SecureString."
}

variable "pushover_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Pushover API token for notifications. Leave empty to disable Pushover."
}

variable "pushover_user" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Pushover user key. Required if pushover_token is set."
}

variable "instance_type" {
  type    = string
  default = "t4g.nano"
}

variable "eip_allocation_id" {
  type        = string
  default     = ""
  description = "Optional: existing EIP allocation ID (e.g. eipalloc-xxx) to attach to the instance. If empty, Terraform creates a new EIP."
}

variable "ssh_cidr" {
  type        = string
  default     = ""
  description = "Optional: your IP/32 to allow SSH (e.g. 1.2.3.4/32). Leave empty to use SSM Session Manager only."
}

variable "app_s3_uri" {
  type        = string
  default     = ""
  description = "Optional: S3 URI of app tarball (e.g. s3://bucket/deploy/app.tar.gz). If set, instance downloads this instead of cloning Git. Use for testing from local without pushing to a repo; base_context stays in S3 only."
}

variable "git_repo_url" {
  type        = string
  default     = ""
  description = "Git repo URL for the career-chatbot code (HTTPS). Instance clones this at boot when app_s3_uri is empty."
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "context_prefix" {
  type        = string
  default     = "context/"
  description = "S3 prefix in the context bucket holding base_context files (PDFs, summary.txt)."
}

variable "allow_http_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to reach the Gradio app (port 7860). Restrict for production."
}
