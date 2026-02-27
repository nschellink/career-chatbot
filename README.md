# Career Chatbot

A Gradio chat app that answers questions about a person’s background using context documents (PDFs, summary text) and OpenAI. Optional Pushover notifications. Deploys to AWS (EC2, optional CloudFront + custom domain).

## Run locally

- **Python 3.10+** (3.11 or 3.14 recommended).

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt
# Or use the lock for exact versions:
# .venv/bin/pip install -r requirements-lock.txt
```

- Put your OpenAI key in `.env` (or set `OPENAI_API_KEY`). Optional: `PUSHOVER_TOKEN`, `PUSHOVER_USER` for notifications.
- Put context files in `base_context/`: PDFs (e.g. resume, profile) and `summary.txt`. The app loads these for RAG-style answers.

```bash
.venv/bin/python -m app
```

Open http://localhost:7860.

## Deploy to AWS

- **Infra**: Terraform in `infra/` provisions EC2 (Amazon Linux 2023), S3 (context + optional app tarball), SSM (OpenAI key, optional Pushover), optional CloudFront + custom domain.
- **Secrets**: Never commit `infra/terraform.tfvars`. Copy `infra/terraform.tfvars.example`, fill in values, and keep the real file local (it’s in `.gitignore`).
- **Context**: Upload base context (PDFs, `summary.txt`) to `s3://<context_bucket>/<context_prefix>`. The instance syncs this at boot.
- **App code**: Either set `app_s3_uri` and use `infra/deploy-from-local.sh` to pack and upload the app, or set `git_repo_url` so the instance clones this repo.
- **Apply**: `cd infra && terraform init && terraform apply`. Use the `app_url` output to open the app (HTTPS if CloudFront is configured).
- **DNS**: If using a custom domain with CloudFront, point the domain at the CloudFront distribution (CNAME or A alias), not at the EC2 IP. See `infra/TROUBLESHOOTING.md` if the app doesn’t respond.

## Project layout

- `app.py` – Gradio app, SSM/S3 integration, context loading.
- `requirements.txt` / `requirements-lock.txt` – Python deps (lock used on EC2 for reproducible installs).
- `base_context/` – Local context files (PDFs, `summary.txt`). On AWS, context is synced from S3; you can add `base_context/` or `base_context/*.pdf` to `.gitignore` if you don’t want to commit them.
- `infra/` – Terraform (EC2, S3, SSM, CloudFront, Route53), `user_data.sh`, `deploy-from-local.sh`, `validate-user-data.sh`, `TROUBLESHOOTING.md`.

## License

This project is based on an open source template by **Ed Donner**, used under the MIT License. See [LICENSE](LICENSE).

## Acknowledgments

- **Ed Donner** — original open source Python/Gradio template this project is derived from.
    - From his [Udemy Course](https://www.udemy.com/share/10dasB3@TFIe-eRJlSqN_Vawcosw8wlgQb4GGiioG87isOC58SBDzaVmyrKuHXsXFBVZezyVXQ==/)

---

## Before first push to GitHub

- **Do not commit** `infra/terraform.tfvars` (it contains secrets). It is in `.gitignore`.
- **Do not commit** `infra/terraform.tfstate` or `infra/terraform.tfstate.backup` (local state). They are in `.gitignore`.
- Run `git status` and review before pushing; ensure no `.env` or API keys are staged.
