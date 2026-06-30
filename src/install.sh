#!/bin/bash
set -euo pipefail

echo "=== Jenkins + faasd + Docker Installer (CI/CD Safe Mode) ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# --- Centralized Variables ---
JENKINSFILE_PATH_INPUT="Jenkinsfile"

CRED_FILE=${GITHUB_CRED_FILE:-"$SCRIPT_DIR/creds/github-creds.json"}
CRED_FILE_SRC="$SCRIPT_DIR/creds/credentials.xml"
CRED_FILE_DST="/var/lib/jenkins/credentials.xml"

CREDENTIALS_ID="github-creds"

ORG_FILE_SRC="$SCRIPT_DIR/jobs/default-config.xml"
# ORG_JOB_DIR and ORG_JOB_FILE will be defined later after parsing GITHUB_ORG_INPUT

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
JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
if [ "$JAVA_VERSION" -lt 17 ]; then
  echo "❌ Java 17+ JDK required. Install OpenJDK 17 or newer."
  exit 1
else
  echo "✅ Java $JAVA_VERSION JDK detected"
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
if [[ -f "$CRED_FILE" ]]; then
  echo "➡ Reading GitHub credentials from $CRED_FILE..."

  if ! jq empty "$CRED_FILE" >/dev/null 2>&1; then
    echo "❌ Invalid JSON format in $CRED_FILE"
    exit 1
  fi

  GITHUB_TOKEN_INPUT=$(jq -r '.github_token // empty' "$CRED_FILE")
  GITHUB_USER_INPUT=$(jq -r '.github_user // empty' "$CRED_FILE")
  GITHUB_ORG_INPUT=$(jq -r '.github_org // empty' "$CRED_FILE")

  if [[ -z "$GITHUB_TOKEN_INPUT" || -z "$GITHUB_USER_INPUT" || -z "$GITHUB_ORG_INPUT" ]]; then
    echo "❌ Missing GitHub credentials in $CRED_FILE"
    exit 1
  fi

  ORG_JOB_DIR="/var/lib/jenkins/jobs/${GITHUB_ORG_INPUT}-org"
  ORG_JOB_FILE="$ORG_JOB_DIR/config.xml"


  # --- 8) Deploy Jenkins credentials.xml ---
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

else
  echo "⏭ Skipping GitHub credential and pipeline setup (no credential file found)"
fi

# --- 9) Deploy Organization Folder org-folder-config.xml ---
# Create org-folder only if it doesn't exist
echo "➡ Creating Organization Folder job for org: ${GITHUB_ORG_INPUT}"

if [ -f "$ORG_FILE_SRC" ]; then
  echo "➡ Deploying Organization Folder config.xml for org: ${GITHUB_ORG_INPUT}"
  sudo mkdir -p "$ORG_JOB_DIR"
  sed "s|\${GITHUB_ORG}|${GITHUB_ORG_INPUT}|g; \
      s|\${CREDENTIALS_ID}|${CREDENTIALS_ID}|g; \
      s|\${JENKINSFILE_PATH}|${JENKINSFILE_PATH_INPUT}|g" \
      "$ORG_FILE_SRC" | sudo tee "$ORG_JOB_FILE" >/dev/null
  sudo chown -R jenkins:jenkins "$ORG_JOB_DIR"
  echo "✅ Organization Folder job created at $ORG_JOB_DIR"
else
  echo "⏭ Skipping Organization Folder deployment (file not found)"
fi

# --- 11) Deploy repo_init scripts ---
echo "➡ Deploying repo_init scripts to /opt/scripts/ ..."

REPO_INIT_DIR="$SCRIPT_DIR/repo_init"
TARGET_DIR="/opt/scripts"

sudo mkdir -p "$TARGET_DIR"

for script in branch-protection.sh remove-flag.sh update-stack.sh gradlew-permission.sh sync-template.sh; do
  if [ -f "$REPO_INIT_DIR/$script" ]; then
    sudo cp "$REPO_INIT_DIR/$script" "$TARGET_DIR/$script"
    sudo chmod +x "$TARGET_DIR/$script"
    sudo chown jenkins:jenkins "$TARGET_DIR/$script"
    echo "   ✔ $script deployed"
  else
    echo "   ⏭ $script not found, skipping"
  fi
done

if [ -f "$REPO_INIT_DIR/branch-protection-rule.json" ]; then
  sudo cp "$REPO_INIT_DIR/branch-protection-rule.json" "$TARGET_DIR/branch-protection-rule.json"
  sudo chown jenkins:jenkins "$TARGET_DIR/branch-protection-rule.json"
  echo "   ✔ branch-protection-rule.json deployed"
else
  echo "   ⏭ branch-protection-rule.json not found, skipping"
fi

echo "➡ Restarting Jenkins to apply new configuration..."
sudo systemctl restart jenkins

echo "🎯 Installer finished successfully (CI/CD safe, all dependencies verified)"
