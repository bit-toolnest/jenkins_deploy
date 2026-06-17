#!/bin/bash
set -e

REPO="$1"          # current repo name (e.g. my-tool)
ORG="$2"           # your org (e.g. bit-tools)
TEMPLATE_REPO="$3" # full GitHub link (e.g. https://github.com/other-org/tool-template.git)

ADMIN_USER="${ADMIN_USER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$REPO" ] || [ -z "$TEMPLATE_REPO" ] || [ -z "$ORG" ]; then
    echo "Usage: $0 <repo> <org> <template-repo-url>"
    exit 1
fi

if [ -z "$ADMIN_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub credentials not available"
    exit 1
fi

# Derive remote name from URL (strip .git)
TEMPLATE_NAME=$(basename -s .git "$TEMPLATE_REPO")

echo "[INFO] Adding remote for template: $TEMPLATE_NAME"
git remote add "$TEMPLATE_NAME" "$TEMPLATE_REPO" || true

git config --global user.name "Jenkins Automation"
git config --global user.email "jenkins@${ORG}.local"

# Check if there are differences between local main and template main
if ! git diff --quiet HEAD "$TEMPLATE_NAME/main"; then
    echo "[INFO] Differences detected with template, committing linkage..."
    git commit --allow-empty -m "Link template remote: ${TEMPLATE_NAME}"
    git push "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${REPO}.git" HEAD:main || true
else
    echo "[INFO] No differences with template, skipping commit/push."
fi
