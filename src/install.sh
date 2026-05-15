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

  if ! jq empty "$CRED_FILE" >/dev/null 2>&1; then
    echo "❌ Invalid JSON format in $CRED_FILE"
    exit 1
  fi

  GITHUB_TOKEN_INPUT=$(jq -r '.github_token // empty' "$CRED_FILE")
  GITHUB_USER_INPUT=$(jq -r '.github_user // empty' "$CRED_FILE")
  GITHUB_ORG_INPUT=$(jq -r '.github_org // empty' "$CRED_FILE")

  if [[ -z "$GITHUB_TOKEN_INPUT" || -z "$GITHUB_USER_INPUT" ]]; then
    echo "❌ Missing GitHub credentials in $CRED_FILE"
    exit 1
  fi

  # --- 8) Deploy Jenkins credentials.xml ---
  CRED_FILE_SRC="$SCRIPT_DIR/credentials.xml"
  CRED_FILE_DST="/var/lib/jenkins/credentials.xml"

  if [ -f "$CRED_FILE_SRC" ]; then
    echo "➡ Deploying Jenkins credentials.xml"
    sed "s|\${GITHUB_USER}|$GITHUB_USER_INPUT|g; \
         s|\${GITHUB_TOKEN}|$GITHUB_TOKEN_INPUT|g" \
         "$CRED_FILE_SRC" | sudo tee "$CRED_FILE_DST" >/dev/null
    sudo chown jenkins:jenkins "$CRED_FILE_DST"
    echo "✅ Jenkins credentials deployed"
  else
    echo "⏭ Skipping credentials deployment (file not found)"
  fi

  echo "➡ Restarting Jenkins to apply new configuration..."
  sudo systemctl restart jenkins
  echo "✅ Jenkins restarted"
else
  echo "⏭ Skipping GitHub credential and pipeline setup (no credential file found)"
fi

# --- 9) Deploy Organization Folder org-folder-config.xml ---
ORG_JOB_DIR="/var/lib/jenkins/jobs/${GITHUB_ORG_INPUT}-org"
ORG_JOB_FILE="$ORG_JOB_DIR/config.xml"
ORG_FILE_SRC="$SCRIPT_DIR/default-config.xml"
JENKINSFILE_PATH_INPUT="Jenkinsfile"

# Create org-folder only if it doesn't exist
if [ ! -d "$ORG_JOB_DIR" ]; then
  echo "➡ Creating Organization Folder job for org: ${GITHUB_ORG_INPUT}"

  if [ -f "$ORG_FILE_SRC" ]; then
    echo "➡ Deploying Organization Folder config.xml for org: ${GITHUB_ORG_INPUT}"
    sudo mkdir -p "$ORG_JOB_DIR"
    sed "s|\${GITHUB_ORG}|${GITHUB_ORG_INPUT}|g; \
        s|\${CREDENTIALS_ID}|github-creds|g; \
        s|\${JENKINSFILE_PATH}|${JENKINSFILE_PATH_INPUT}|g" \
        "$ORG_FILE_SRC" | sudo tee "$ORG_JOB_FILE" >/dev/null
    sudo chown -R jenkins:jenkins "$ORG_JOB_DIR"
    echo "✅ Organization Folder job created at $ORG_JOB_DIR"
  else
    echo "⏭ Skipping Organization Folder deployment (file not found)"
  fi
else
  echo "⏭ Organization Folder job already exists, skipping"
fi


echo "🎯 Installer finished successfully (CI/CD safe, all dependencies verified)"
