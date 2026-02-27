# App not responding – checklist

When the app URL (e.g. https://chat.nathanschellink.com) doesn’t load, work through these in order.

## 1. On the EC2 instance (SSM Session Manager or SSH)

**1.1 Is the Gradio app running?**

```bash
sudo systemctl status career-chatbot
```

- If **inactive/failed**: check logs:
  ```bash
  sudo journalctl -u career-chatbot -n 80 --no-pager
  ```
  Common causes: missing SSM param, wrong `CONTEXT_LOCAL_DIR`, Python/import error, OOM.

**1.2 Does Gradio respond on localhost?**

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7860/
```

- **200** → app is up; problem is likely Caddy, CloudFront, or DNS (go to step 2).
- **000** or connection refused → app not listening. Fix career-chatbot (logs above) then retry.

**1.3 Does Caddy respond on port 80?**

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/
```

- **200** → Caddy is proxying; problem is likely CloudFront or DNS (step 2).
- **000** or connection refused → check Caddy:
  ```bash
  sudo systemctl status caddy
  sudo journalctl -u caddy -n 30 --no-pager
  ```

---

## 2. CloudFront and DNS (when using custom domain)

**2.1 CloudFront origin = this instance**

If you **replaced** the instance (e.g. taint + apply), CloudFront’s origin domain is updated only when Terraform runs. Ensure Terraform state matches the running instance:

```bash
cd infra
terraform output  # or: terraform state show aws_instance.app
```

- Note `app` instance **public IP** or **public_dns**.
- In AWS Console → CloudFront → your distribution → Origin: the **Origin domain** should be the **current** instance’s public DNS (e.g. `ec2-xx-xx-xx-xx.us-west-1.compute.amazonaws.com`). If it still points to an old instance’s hostname, run:

  ```bash
  terraform apply -replace=aws_instance.app
  ```
  or run a normal `terraform apply` so the distribution’s origin is refreshed from state.

**2.2 DNS points to CloudFront**

You use `manage_app_dns_record = false`, so you manage the record yourself.

- **chat.nathanschellink.com** must resolve to your CloudFront distribution:
  - **CNAME** `chat.nathanschellink.com` → `d1234abcd.cloudfront.net` (from `terraform output cloudfront_domain`), or  
  - **A (alias)** `chat.nathanschellink.com` → CloudFront distribution (alias target).

Check from your machine:

```bash
dig +short chat.nathanschellink.com
# or
nslookup chat.nathanschellink.com
```

You should see CloudFront IPs or the alias target, not the EC2 public IP (viewers must hit CloudFront, which then hits the origin).

**2.3 Security group**

With CloudFront, the app security group allows **port 80 only from the CloudFront prefix list**. Direct browser access to the instance’s public IP on port 80 will be blocked; that’s expected. Traffic must go: Browser → **https://chat.nathanschellink.com** → CloudFront → EC2:80.

---

## 3. Quick recap

| Check | Command / action |
|-------|-------------------|
| career-chatbot running | `sudo systemctl status career-chatbot` |
| Gradio answers on 7860 | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:7860/` → 200 |
| Caddy answers on 80 | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/` → 200 |
| CloudFront origin | Console or `terraform state show` → origin = current instance public_dns |
| DNS | `dig chat.nathanschellink.com` → CloudFront, not EC2 IP |

Run step 1 on the instance first; if both curl commands return 200, the issue is almost certainly CloudFront origin or DNS (steps 2.1 and 2.2).
