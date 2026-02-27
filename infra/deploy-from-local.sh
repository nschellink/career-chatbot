#!/usr/bin/env bash
# Package the app (excluding base_context and secrets) and upload to S3 for deploy-from-local.
# Usage: ./deploy-from-local.sh [S3_BUCKET]
#   S3_BUCKET = context bucket name (default: from terraform output context_bucket)
# Uses AWS_PROFILE if set (e.g. career-chat-admin for SSO); otherwise default AWS config.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ -n "$1" ]]; then
  BUCKET="$1"
else
  BUCKET=$(terraform -chdir="$SCRIPT_DIR" output -raw context_bucket 2>/dev/null || true)
  if [[ -z "$BUCKET" ]]; then
    echo "Usage: $0 [S3_BUCKET]"
    echo "  S3_BUCKET = your context bucket (e.g. from: terraform -chdir=infra output context_bucket)"
    exit 1
  fi
fi

REGION="${AWS_REGION:-$(grep -E '^\s*region\s*=' "$SCRIPT_DIR/terraform.tfvars" 2>/dev/null | sed 's/.*= *"\(.*\)".*/\1/' || echo "us-west-1")}"
TARBALL="/tmp/career-chatbot-app.tar.gz"
PACKDIR="/tmp/career-chatbot-pack-$$"
mkdir -p "$PACKDIR"

echo "Building tarball (app.py, requirements.txt, requirements-lock.txt if present)..."
PACK_FILES="app.py requirements.txt"
if [[ -f "$PROJECT_ROOT/requirements-lock.txt" ]]; then
  PACK_FILES="$PACK_FILES requirements-lock.txt"
fi
for f in $PACK_FILES; do
  if [[ ! -f "$PROJECT_ROOT/$f" ]]; then
    echo "Error: $f not found in $PROJECT_ROOT" >&2
    rm -rf "$PACKDIR"
    exit 1
  fi
  cp "$PROJECT_ROOT/$f" "$PACKDIR/"
done
tar czf "$TARBALL" -C "$PACKDIR" $PACK_FILES
rm -rf "$PACKDIR"
echo "Tarball contents:"
tar tzf "$TARBALL"

echo "Uploading to s3://$BUCKET/deploy/app.tar.gz (region $REGION)..."
aws s3 cp "$TARBALL" "s3://$BUCKET/deploy/app.tar.gz" --region "$REGION"
rm -f "$TARBALL"

echo "Done. Add to terraform.tfvars:"
echo "  app_s3_uri = \"s3://$BUCKET/deploy/app.tar.gz\""
echo "  # Comment out or leave empty: git_repo_url"
echo "Then run: terraform -chdir=infra apply"
