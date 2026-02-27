#!/bin/bash
set -e
APP_NAME="${app_name}"
APP_DIR="${app_dir}"
CONTEXT_BUCKET="${context_bucket}"
CONTEXT_PREFIX="${context_prefix}"
APP_S3_URI="${app_s3_uri}"
GIT_REPO="${git_repo_url}"
GIT_BRANCH="${git_branch}"
AWS_REGION="${aws_region}"
SSM_OPENAI="${ssm_openai_param}"
SSM_PUSHOVER_TOKEN="${ssm_pushover_token}"
SSM_PUSHOVER_USER="${ssm_pushover_user}"
USE_CLOUDFRONT="${use_cloudfront}"
APP_DOMAIN="${app_domain}"

# Enable serial console login (ttyS0) for EC2 Serial Console
if systemctl list-unit-files 2>/dev/null | grep -q serial-getty@ttyS0; then
  systemctl enable serial-getty@ttyS0.service 2>/dev/null || true
  systemctl start serial-getty@ttyS0.service 2>/dev/null || true
fi

# Install and enable SSM agent for Session Manager
ARCH=$(uname -m)
case "$ARCH" in
  aarch64) SSM_RPM="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_arm64/amazon-ssm-agent.rpm" ;;
  x86_64)  SSM_RPM="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm" ;;
  *)       SSM_RPM="" ;;
esac
if [[ -n "$SSM_RPM" ]]; then
  dnf install -y "$SSM_RPM" 2>/dev/null || true
  systemctl enable amazon-ssm-agent 2>/dev/null || true
  systemctl start amazon-ssm-agent 2>/dev/null || true
fi

# Prefer Python 3.14 → 3.12 → 3.11 for the app venv; fall back to system python3 (3.9).
dnf install -y python3 git wget
if dnf install -y python3.14 2>/dev/null; then
  PYTHON_FOR_VENV="python3.14"
elif dnf install -y python3.12 2>/dev/null; then
  PYTHON_FOR_VENV="python3.12"
elif dnf install -y python3.11 2>/dev/null; then
  PYTHON_FOR_VENV="python3.11"
else
  PYTHON_FOR_VENV="python3"
fi

# App source: S3 tarball (deploy from local) or Git clone
mkdir -p "$(dirname "$APP_DIR")"
if [[ -n "$APP_S3_URI" ]]; then
  mkdir -p "$APP_DIR"
  TMPTAR="/tmp/app.tar.gz"
  if ! aws s3 cp "$APP_S3_URI" "$TMPTAR" --region "$AWS_REGION"; then
    echo "Failed to download app from $APP_S3_URI" >&2
    exit 1
  fi
  if ! tar -xzf "$TMPTAR" -C "$APP_DIR"; then
    echo "Failed to extract app tarball" >&2
    exit 1
  fi
  rm -f "$TMPTAR"
else
  git clone --branch "$GIT_BRANCH" --depth 1 "$GIT_REPO" "$APP_DIR" || { echo "git clone failed"; exit 1; }
fi

# Repo root: directory containing requirements.txt or requirements-lock.txt (top level or subdir)
REPO_ROOT="$APP_DIR"
if [[ ! -f "$APP_DIR/requirements.txt" && ! -f "$APP_DIR/requirements-lock.txt" ]]; then
  FOUND=$(find "$APP_DIR" -maxdepth 3 \( -name "requirements.txt" -o -name "requirements-lock.txt" \) -type f 2>/dev/null | head -1)
  if [[ -n "$FOUND" ]]; then
    REPO_ROOT=$(dirname "$FOUND")
  else
    echo "requirements.txt or requirements-lock.txt not found in $APP_DIR (tarball may be wrong or empty). Contents:" >&2
    ls -la "$APP_DIR" >&2
    exit 1
  fi
fi

# Sync context from S3 (base_context; not in Git)
mkdir -p "$APP_DIR/base_context"
aws s3 sync "s3://$CONTEXT_BUCKET/$CONTEXT_PREFIX" "$APP_DIR/base_context" --region "$AWS_REGION" || true

# Dependencies in a venv using Python 3.11 (or 3.9 fallback); use lock file if present
$PYTHON_FOR_VENV -m venv "$REPO_ROOT/venv"
"$REPO_ROOT/venv/bin/pip" install --upgrade pip
if [[ -f "$REPO_ROOT/requirements-lock.txt" ]]; then
  "$REPO_ROOT/venv/bin/pip" install -r "$REPO_ROOT/requirements-lock.txt"
else
  "$REPO_ROOT/venv/bin/pip" install -r "$REPO_ROOT/requirements.txt"
fi

# Gradio: bind to localhost when behind CloudFront
if [[ "$USE_CLOUDFRONT" == "true" ]]; then
  GRADIO_SERVER_NAME="127.0.0.1"
else
  GRADIO_SERVER_NAME="0.0.0.0"
fi

# Systemd unit
cat > /etc/systemd/system/career-chatbot.service << EOF
[Unit]
Description=Career Chatbot Gradio App
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=$REPO_ROOT
Environment=CONTEXT_LOCAL_DIR=$APP_DIR/base_context
Environment=AWS_REGION=$AWS_REGION
Environment=SSM_OPENAI_KEY_PARAM=$SSM_OPENAI
Environment=SSM_PUSHOVER_TOKEN_PARAM=$SSM_PUSHOVER_TOKEN
Environment=SSM_PUSHOVER_USER_PARAM=$SSM_PUSHOVER_USER
Environment=GRADIO_SERVER_NAME=$GRADIO_SERVER_NAME
Environment=GRADIO_SERVER_PORT=7860
ExecStart=$REPO_ROOT/venv/bin/python -m app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

chown -R ec2-user:ec2-user "$APP_DIR"
systemctl daemon-reload
systemctl enable career-chatbot
systemctl start career-chatbot

# Caddy reverse proxy when using CloudFront
if [[ "$USE_CLOUDFRONT" == "true" ]]; then
  CADDY_VERSION="2.7.6"
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && CADDY_ARCH="amd64" || CADDY_ARCH="arm64"
  wget -q "https://github.com/caddyserver/caddy/releases/download/v$${CADDY_VERSION}/caddy_$${CADDY_VERSION}_linux_$${CADDY_ARCH}.tar.gz" -O /tmp/caddy.tar.gz
  tar -xzf /tmp/caddy.tar.gz -C /usr/bin caddy
  rm /tmp/caddy.tar.gz
  chmod 755 /usr/bin/caddy
  setcap 'cap_net_bind_service=+ep' /usr/bin/caddy 2>/dev/null || true
  mkdir -p /etc/caddy
  cat > /etc/caddy/Caddyfile << EOF
:80 {
  reverse_proxy 127.0.0.1:7860 {
    header_up X-Forwarded-Proto "https"
    header_up X-Forwarded-Host "$APP_DOMAIN"
  }
}
EOF
  chown -R root:root /etc/caddy
  mkdir -p /var/lib/caddy/.local/share/caddy
  chown -R root:root /var/lib/caddy
  cat > /etc/systemd/system/caddy.service << 'CADDYEOF'
[Unit]
Description=Caddy reverse proxy for Gradio
After=network.target career-chatbot.service

[Service]
Type=simple
WorkingDirectory=/var/lib/caddy
Environment=HOME=/var/lib/caddy
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
Restart=on-failure
RestartSec=5
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
CADDYEOF
  systemctl daemon-reload
  systemctl enable caddy
  systemctl start caddy
fi
