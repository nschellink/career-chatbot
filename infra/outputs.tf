output "instance_id" {
  value       = aws_instance.app.id
  description = "EC2 instance ID"
}

output "public_ip" {
  value       = local.app_public_ip
  description = "Elastic IP of the chatbot instance (stable across restarts)"
}

output "app_url" {
  value       = local.use_cloudfront ? "https://${var.app_domain}" : "http://${local.app_public_ip}:7860"
  description = "Use this URL to open the app in your browser (HTTPS if CloudFront is enabled, else HTTP on port 7860)"
}

output "cloudfront_domain" {
  value       = local.use_cloudfront && !var.manage_app_dns_record ? aws_cloudfront_distribution.app[0].domain_name : null
  description = "When using CloudFront and not managing DNS: point your manual record (A alias or CNAME) to this domain."
}

output "cloudfront_origin_hostname" {
  value       = local.use_cloudfront ? aws_instance.app.public_dns : null
  description = "Current CloudFront origin (instance public DNS). If you replaced the instance, run 'terraform apply' so CloudFront uses this."
}

output "context_bucket" {
  value       = aws_s3_bucket.context.id
  description = "S3 bucket name; upload base_context files to s3://<bucket>/<context_prefix>"
}

output "context_prefix" {
  value       = var.context_prefix
  description = "S3 prefix for context files"
}
