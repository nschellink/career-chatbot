#!/usr/bin/env bash
# Validate user_data install steps locally using Docker (Amazon Linux 2023).
# Catches: missing packages (wget, python3.11), pip/venv issues, lock file conflicts.
# Usage: ./validate-user-data.sh
# Requires: Docker (docker pull amazonlinux:2023)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="/opt/career-chatbot"

if ! command -v docker &>/dev/null; then
  echo "Docker is required. Install Docker and run: docker pull amazonlinux:2023" >&2
  exit 1
fi

echo "=== Validating user_data steps in Amazon Linux 2023 container ==="
echo "Project root: $PROJECT_ROOT"
echo ""

# Same files deploy-from-local.sh packs
PACK_FILES="app.py requirements.txt"
MOUNT_ARGS=(
  -v "$PROJECT_ROOT/app.py:/tmp/app.py:ro"
  -v "$PROJECT_ROOT/requirements.txt:/tmp/requirements.txt:ro"
)
if [[ -f "$PROJECT_ROOT/requirements-lock.txt" ]]; then
  PACK_FILES="$PACK_FILES requirements-lock.txt"
  MOUNT_ARGS+=( -v "$PROJECT_ROOT/requirements-lock.txt:/tmp/requirements-lock.txt:ro" )
fi
for f in app.py requirements.txt; do
  if [[ ! -f "$PROJECT_ROOT/$f" ]]; then
    echo "Error: $f not found in $PROJECT_ROOT" >&2
    exit 1
  fi
done

docker run --rm \
  "${MOUNT_ARGS[@]}" \
  amazonlinux:2023 \
  bash -e -c '
    echo "--- Installing packages (python3, git, wget, prefer python3.14/3.12/3.11) ---"
    dnf install -y python3 git wget >/dev/null
    if dnf install -y python3.14 2>/dev/null; then
      PYTHON_FOR_VENV="python3.14"
      echo "Using python3.14 for venv"
    elif dnf install -y python3.12 2>/dev/null; then
      PYTHON_FOR_VENV="python3.12"
      echo "Using python3.12 for venv"
    elif dnf install -y python3.11 2>/dev/null; then
      PYTHON_FOR_VENV="python3.11"
      echo "Using python3.11 for venv"
    else
      PYTHON_FOR_VENV="python3"
      echo "Using python3 for venv"
    fi

    echo "--- Setting up app dir (simulating tarball extract) ---"
    mkdir -p "'"$APP_DIR"'"
    cp /tmp/app.py /tmp/requirements.txt "'"$APP_DIR"'/"
    [[ -f /tmp/requirements-lock.txt ]] && cp /tmp/requirements-lock.txt "'"$APP_DIR"'/"
    REPO_ROOT="'"$APP_DIR"'"

    echo "--- Creating venv and installing dependencies ---"
    $PYTHON_FOR_VENV -m venv "$REPO_ROOT/venv"
    "$REPO_ROOT/venv/bin/pip" install --upgrade pip -q
    if [[ -f "$REPO_ROOT/requirements-lock.txt" ]]; then
      "$REPO_ROOT/venv/bin/pip" install -r "$REPO_ROOT/requirements-lock.txt" -q
    else
      "$REPO_ROOT/venv/bin/pip" install -r "$REPO_ROOT/requirements.txt" -q
    fi

    echo "--- Verifying app can start (import only) ---"
    cd "$REPO_ROOT" && "$REPO_ROOT/venv/bin/python" -c "import app; print(\"app import OK\")"

    echo "--- Caddy download (wget) ---"
    CADDY_VERSION="2.7.6"
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && CADDY_ARCH="amd64" || CADDY_ARCH="arm64"
    wget -q "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${CADDY_ARCH}.tar.gz" -O /tmp/caddy.tar.gz
    tar -tzf /tmp/caddy.tar.gz | head -1
    echo "Caddy tarball OK"

    echo ""
    echo "=== All steps completed successfully ==="
  '

echo "Done. Same steps should succeed on EC2 user_data."
