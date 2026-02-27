# When using CloudFront: alias A record to the distribution (skipped if manage_app_dns_record = false).
resource "aws_route53_record" "app_cloudfront" {
  count   = local.use_cloudfront && var.manage_app_dns_record ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.app_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.app[0].domain_name
    zone_id                = aws_cloudfront_distribution.app[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# When not using CloudFront: A record to EC2 public IP (skipped if manage_app_dns_record = false).
resource "aws_route53_record" "app_direct" {
  count   = var.hosted_zone_id != "" && var.app_domain != "" && !local.use_cloudfront && var.manage_app_dns_record ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.app_domain
  type    = "A"
  ttl     = 300
  records = [aws_instance.app.public_ip]
}
