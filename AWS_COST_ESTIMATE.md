# AWS Cost Estimate - Career Chatbot

**Region:** us-west-1 (primary); ACM in us-east-1 when using CloudFront  
**Date:** February 2026  
**Architecture:** EC2 + CloudFront (optional) + S3 + SSM; custom domain via your ACM cert and Route53

---

## Infrastructure Summary

| Component | Description |
|-----------|-------------|
| **EC2** | t4g.nano (ARM), Amazon Linux 2023, 30 GB gp3 root volume |
| **Elastic IP** | One EIP (existing or Terraform-created); no charge when attached to running instance |
| **CloudFront** | Optional: 1 distribution when `app_domain` + `hosted_zone_id` set; HTTPS via your ACM cert, origin = EC2:80 |
| **S3** | One bucket: context files + optional deploy tarball; versioning, SSE-S3 (AES256) |
| **SSM Parameter Store** | OpenAI API key + optional Pushover (SecureString, AWS-managed key) |
| **Route53** | Uses your existing hosted zone; optional A/alias record (or you manage DNS yourself) |
| **ACM** | You create and validate the cert in us-east-1; no Terraform-managed cert; public certs = no charge |
| **IAM** | Instance profile + policies; no additional cost |

---

## Monthly Cost Breakdown

### 1. EC2 Compute (t4g.nano, us-west-1)

**Instance:** t4g.nano (2 vCPU, 0.5 GiB RAM, ARM)
- **On-Demand:** ~$0.0042/hour
- **Monthly:** $0.0042 × 730 ≈ **$3.07**

**EBS (gp3) – root volume:**
- **Size:** 30 GB (required by AL2023 AMI snapshot)
- **Storage:** 30 × $0.08/GB-month ≈ **$2.40**
- **IOPS:** 3,000 baseline included

**EC2 subtotal:** **~$5.47/month**

---

### 2. Elastic IP (EIP)

- **Attached to running instance:** **$0/month**
- **Allocated but not attached:** ~$0.005/hour ≈ **~$3.65/month**

*Terraform either attaches an existing EIP or creates one and attaches it; normal use = $0.*

---

### 3. Amazon CloudFront (when using custom domain)

Used when `app_domain` and `hosted_zone_id` are set.

- **Data transfer out to viewers:** $0.085/GB (first 10 TB)
- **HTTPS requests:** $0.0100 per 10,000 requests
- **Origin (EC2 in us-west-1):** No charge for origin fetch from same region.

**Low-traffic estimate (e.g. personal chatbot):**
- 5 GB/month transfer: 5 × $0.085 ≈ **$0.43**
- 100,000 requests: 10 × $0.01 ≈ **$0.10**  
**CloudFront subtotal:** **~$0.50/month** (can be $0 in Free Tier for first 12 months: 1 TB out, 10M requests free)

---

### 4. Amazon S3 (us-west-1)

- **Storage:** Context files + optional deploy tarball; assume &lt;1 GB
  - 1 GB × $0.023/GB-month ≈ **$0.02**
- **Requests:** PUT/GET minimal (sync at boot, occasional uploads); first 1,000 PUT, 1,000 GET free
- **S3 subtotal:** **~$0.02/month**

---

### 5. AWS Systems Manager Parameter Store

- **Standard parameters:** No charge (up to 10,000 parameters)
- **SecureString:** Uses AWS-managed key (`alias/aws/ssm`); **no KMS key fee**
- **SSM subtotal:** **$0/month**

---

### 6. Route53

- **Hosted zone:** You use an existing zone; **$0** additional (zone already billed elsewhere if applicable)
- **Queries:** $0.40 per million; &lt;10k/month ≈ **$0**
- **Route53 subtotal:** **$0/month**

---

### 7. Data Transfer

- **Outbound (EC2 → internet):** First 100 GB/month free (us-west-1); typical chatbot use &lt;10 GB → **$0**
- **CloudFront → viewers:** Included in CloudFront section above
- **Data transfer subtotal:** **$0/month** for assumed usage

---

### 8. ACM (Certificate Manager)

- **Public certificates:** **$0**
- You create/validate the cert in us-east-1 yourself; Terraform does not create ACM resources.

---

## Total Monthly Cost Estimate

| Scenario | EC2 + EBS | EIP | CloudFront | S3 | SSM | Route53 | **Total** |
|----------|-----------+-----+------------+----+-----+---------|-----------|
| **With CloudFront** (custom domain) | $5.47 | $0 | ~$0.50 | ~$0.02 | $0 | $0 | **~$6/month** |
| **Without CloudFront** (IP:7860 only) | $5.47 | $0 | — | ~$0.02 | $0 | $0 | **~$5.50/month** |

*CloudFront can be $0 in Free Tier (first 12 months). EIP = $0 when attached.*

---

## Cost Optimization

- **Reserved Instance (1-year, t4g.nano):** ~50% savings on compute → **~$1.50/month** off EC2.
- **Spot (t4g.nano):** ~80% savings; risk of interruption (often fine for personal apps).
- **CloudFront Free Tier:** 1 TB data out + 10M HTTPS requests free for 12 months after sign-up.

---

## Assumptions

1. **Region:** us-west-1 for EC2, S3, SSM; us-east-1 only for your ACM cert (CloudFront requirement).
2. **EC2:** Running 24/7 (730 hours/month); 30 GB root volume (AL2023 minimum).
3. **Traffic:** Low (personal/professional chatbot); &lt;10 GB out, &lt;100k CloudFront requests.
4. **EIP:** Attached to the instance (no idle EIP charge).
5. **No customer KMS keys:** SSM uses `aws/ssm`; S3 uses SSE-S3 (AES256).

---

## Exclusions

- **OpenAI API** and **Pushover** (external APIs)
- **Domain registration**
- **Route53 hosted zone** (if you create a new one: $0.50/month)
- **CloudWatch Logs** (optional; typically &lt;$0.50 at low volume)
- **Backups** (none defined in Terraform)

---

*Pricing is approximate and based on public list prices (us-west-1 where applicable). For exact figures use [AWS Pricing Calculator](https://calculator.aws/) or your billing console.*
