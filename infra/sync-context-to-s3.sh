#!/usr/bin/env bash
# Upload base_context (PDFs, summary.txt) to S3 so the instance has the latest context.
# The instance syncs this at boot; if the instance is already running, run the sync + restart steps below.
# Usage: ./sync-context-to-s3.sh [S3_BUCKET] [CONTEXT_PREFIX]
#   S3_BUCKET      = context bucket (default: from terraform output context_bucket)
#   CONTEXT_PREFIX = prefix in bucket (default: from terraform output context_prefix)
# Uses AWS_PROFILE if set (e.g. career-chat-admin for SSO).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ ! -d "$PROJECT_ROOT/base_context" ]]; then
  echo "Error: base_context/ not found in $PROJECT_ROOT" >&2
  exit 1
fi

if [[ -n "$1" ]]; then
  BUCKET="$1"
else
  BUCKET=$(terraform -chdir="$SCRIPT_DIR" output -raw context_bucket 2>/dev/null || true)
  if [[ -z "$BUCKET" ]]; then
    echo "Usage: $0 [S3_BUCKET] [CONTEXT_PREFIX]"
    echo "  Get bucket from: terraform -chdir=infra output context_bucket"
    exit 1
  fi
fi

PREFIX="${2:-$(terraform -chdir="$SCRIPT_DIR" output -raw context_prefix 2>/dev/null || echo "context/")}"
REGION="${AWS_REGION:-$(grep -E '^\s*region\s*=' "$SCRIPT_DIR/terraform.tfvars" 2>/dev/null | sed 's/.*= *"\(.*\)".*/\1/' || echo "us-west-1")}"

echo "Syncing base_context/ to s3://$BUCKET/$PREFIX (region $REGION)..."
aws s3 sync "$PROJECT_ROOT/base_context" "s3://$BUCKET/$PREFIX" --region "$REGION"
echo "Done. Context on instance is updated at next boot, or run the following on the instance to update now:"
echo "  aws s3 sync s3://$BUCKET/$PREFIX /opt/career-chatbot/base_context --region $REGION"
echo "  sudo systemctl restart career-chatbot"
