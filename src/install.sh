#!/bin/bash
set -euo pipefail

echo "=== Jenkins + faasd + Docker Installer (CI/CD Safe Mode) ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Helper Functions ---
check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ $1 not found. Please install $1 before running this installer."
    exit 1
  else
    echo "✅ $1 detected"
  fi
}

install_pkg() {
  PKG="$1"
  if command -v apt >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$PKG"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "$PKG"
  else
    echo "❌ Unsupported package manager. Install $PKG manually."
    exit 1
  fi
}

# --- 1) Verify Java 17 JDK ---
if ! java -version 2>&1 | grep -q 'version "17'; then
  echo "❌ Java 17 JDK not found. Install OpenJDK 17 first."
  exit 1
else
  echo "✅ Java 17 JDK detected"
fi

# --- 2) Verify faas-cli ---
check_cmd faas-cli

# --- 3) Verify Docker ---
check_cmd docker

# --- 4) Verify Jenkins service ---
if ! systemctl is-active --quiet jenkins; then
  echo "❌ Jenkins is not running. Please install/start Jenkins."
  exit 1
else
  echo "✅ Jenkins running"
fi

# --- 5) Add Jenkins user to docker group ---
echo "➡ Adding Jenkins user to docker group..."
sudo usermod -aG docker jenkins || true

# --- 6) Install jq/xmlstarlet for credential parsing ---
install_pkg jq
install_pkg xmlstarlet

# --- 7) GitHub credentials setup ---
CRED_FILE=${GITHUB_CRED_FILE:-"$SCRIPT_DIR/github-creds.json"}
if [[ -f "$CRED_FILE" ]]; then
  echo "➡ Reading GitHub credentials from $CRED_FILE..."

  if [[ "$CRED_FILE" == *.json ]]; then
    GITHUB_TOKEN_INPUT=$(jq -r '.token' "$CRED_FILE")
    GITHUB_ADMIN_USER_INPUT=$(jq -r '.admin_user' "$CRED_FILE")
    GITHUB_ORG_INPUT=$(jq -r '.org' "$CRED_FILE")
  elif [[ "$CRED_FILE" == *.xml ]]; then
    GITHUB_TOKEN_INPUT=$(xmlstarlet sel -t -v "//credentials/token" "$CRED_FILE")
    GITHUB_ADMIN_USER_INPUT=$(xmlstarlet sel -t -v "//credentials/admin_user" "$CRED_FILE")
    GITHUB_ORG_INPUT=$(xmlstarlet sel -t -v "//credentials/org" "$CRED_FILE")
  else
    echo "❌ Unsupported credential file format: $CRED_FILE"
    exit 1
  fi

  # --- 8) Deploy Jenkins credentials.xml ---
  CRED_FILE_SRC="$SCRIPT_DIR/credentials.xml"
  CRED_FILE_DST="/var/lib/jenkins/credentials.xml"

  if [ -f "$CRED_FILE_SRC" ]; then
    echo "➡ Deploying Jenkins credentials.xml"
    sed "s|\${GITHUB_ADMIN_USER}|$GITHUB_ADMIN_USER_INPUT|g; s|\${GITHUB_TOKEN}|$GITHUB_TOKEN_INPUT|g" \
      "$CRED_FILE_SRC" | sudo tee "$CRED_FILE_DST" >/dev/null
    sudo chown jenkins:jenkins "$CRED_FILE_DST"
    echo "✅ Jenkins credentials deployed"
  else
    echo "⏭ Skipping credentials deployment (file not found)"
  fi

  # --- 9) Deploy Organization Folder config.xml ---
  ORG_JOB_DIR="/var/lib/jenkins/jobs/${GITHUB_ORG}-org"
  ORG_JOB_FILE="$ORG_JOB_DIR/config.xml"
  ORG_FILE_SRC="$SCRIPT_DIR/org-folder-config.xml"

  if [ -f "$ORG_FILE_SRC" ]; then
    echo "➡ Deploying Organization Folder config.xml for org: ${GITHUB_ORG}"
    sudo mkdir -p "$ORG_JOB_DIR"
    sudo cp "$ORG_FILE_SRC" "$ORG_JOB_FILE"
    sudo chown -R jenkins:jenkins "$ORG_JOB_DIR"
    echo "✅ Organization Folder job created at $ORG_JOB_DIR"
  else
    echo "⏭ Skipping Organization Folder deployment (file not found)"
  fi

  echo "➡ Restarting Jenkins to apply new configuration..."
  sudo systemctl restart jenkins
  echo "✅ Jenkins restarted"
else
  echo "⏭ Skipping GitHub credential and pipeline setup (no credential file found)"
fi

echo "🎯 Installer finished successfully (CI/CD safe, all dependencies verified)"
