#!/bin/bash
set -e

echo "=== Jenkins + faasd + Docker Installer (Dependency Check Mode) ==="

# 1) Verify Java 17 JDK
if ! java -version 2>&1 | grep -q "17"; then
  echo "❌ Java 17 JDK not found. Please install OpenJDK 17 before running this installer."
  exit 1
else
  echo "✅ Java 17 JDK detected"
fi

# 2) Verify faasd
if ! command -v faasd >/dev/null 2>&1; then
  echo "❌ faasd not found. Please install faasd before running this installer."
  exit 1
else
  echo "✅ faasd detected"
fi

# 3) Verify Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker not found. Please install Docker before running this installer."
  exit 1
else
  echo "✅ Docker detected"
fi

# 4) Verify Jenkins
if ! systemctl status jenkins >/dev/null 2>&1; then
  echo "❌ Jenkins service not found. Please install Jenkins before running this installer."
  exit 1
else
  echo "✅ Jenkins detected"
fi

# 5) Add Jenkins user to docker group
echo "➡ Adding Jenkins user to docker group..."
sudo usermod -aG docker jenkins || true

# 6) Optional GitHub credentials setup
echo ""
echo "➡ Do you want to configure GitHub credentials for branch protection automation? (yes/no)"
read -r ADD_GITHUB_CREDS

if [[ "$ADD_GITHUB_CREDS" == "yes" || "$ADD_GITHUB_CREDS" == "y" ]]; then
    echo ""
    echo "➡ Enter GitHub Personal Access Token:"
    read -r GITHUB_TOKEN_INPUT

    echo "➡ Enter GitHub Admin Username:"
    read -r GITHUB_ADMIN_USER_INPUT

    echo "➡ Enter GitHub Organization Name:"
    read -r GITHUB_ORG_INPUT

    echo "➡ Writing environment variables to /etc/environment..."
    sudo sed -i '/GITHUB_TOKEN=/d' /etc/environment
    sudo sed -i '/GITHUB_ADMIN_USER=/d' /etc/environment
    sudo sed -i '/GITHUB_ORG=/d' /etc/environment

    echo "GITHUB_TOKEN=${GITHUB_TOKEN_INPUT}" | sudo tee -a /etc/environment >/dev/null
    echo "GITHUB_ADMIN_USER=${GITHUB_ADMIN_USER_INPUT}" | sudo tee -a /etc/environment >/dev/null
    echo "GITHUB_ORG=${GITHUB_ORG_INPUT}" | sudo tee -a /etc/environment >/dev/null

    echo "➡ Reloading environment..."
    source /etc/environment || true

    echo "➡ Restarting Jenkins to apply new environment variables..."
    sudo systemctl restart jenkins
    echo "✅ Jenkins restarted and environment variables applied"
else
    echo "⏭ Skipping GitHub credential setup as per user choice"
fi

echo "🎯 Installer finished successfully (all dependencies verified)"
