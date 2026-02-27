# ACM certificate is not created by Terraform.
#
# CloudFront requires an ACM certificate in us-east-1 for your custom domain
# (e.g. chat.nathanschellink.com). Create and validate the certificate in AWS yourself:
#
#   1. In AWS Console: Certificate Manager (ACM) — make sure you're in us-east-1.
#   2. Request a public certificate for your domain (e.g. chat.nathanschellink.com).
#   3. Use DNS validation: add the CNAME record ACM shows into your hosted zone.
#   4. After the certificate is issued, copy its ARN and set acm_certificate_arn in terraform.tfvars.
#
# Your existing A record for the app (e.g. chat.nathanschellink.com) is left as-is when
# manage_app_dns_record = false; point that A record (or CNAME) to the CloudFront
# distribution domain after the first apply (see output cloudfront_domain).
