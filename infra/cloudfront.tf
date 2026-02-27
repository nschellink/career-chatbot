# CloudFront in front of EC2: HTTPS for viewers, HTTP to origin (nginx on port 80).
# Origin is restricted by security group to CloudFront IP ranges only.
resource "aws_cloudfront_distribution" "app" {
  count   = local.use_cloudfront ? 1 : 0
  enabled = true

  lifecycle {
    precondition {
      condition     = !local.use_cloudfront || var.acm_certificate_arn != ""
      error_message = "When using CloudFront (app_domain + hosted_zone_id set), acm_certificate_arn must be set. Create an ACM certificate in us-east-1, validate it via DNS, then set the ARN in terraform.tfvars."
    }
  }
  comment = "${var.app_name} Gradio app"
  aliases = [var.app_domain]

  origin {
    domain_name = aws_instance.app.public_dns
    origin_id   = "ec2-origin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy  = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout     = 60
      origin_keepalive_timeout = 5
    }
    # CloudFront does not allow overriding the Host header. The origin receives
    # Host: <origin domain_name>. CloudFront sends X-Forwarded-Host with the
    # viewer host (e.g. chat.nathanschellink.com) so the app can use that for URLs.
  }

  default_cache_behavior {
    target_origin_id       = "ec2-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress              = true
    cache_policy_id       = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # Managed-AllViewer
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { App = var.app_name }
}
