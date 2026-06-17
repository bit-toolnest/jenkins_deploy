#!/bin/bash
set -e

REPO="$1"          # current repo name (e.g. my-tool)
ORG="$2"           # your org (e.g. bit-template)
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

# Derive remote name from URL
TEMPLATE_NAME=$(basename -s .git "$TEMPLATE_REPO")

echo "[INFO] Syncing changes from template: $TEMPLATE_NAME"
git fetch "$TEMPLATE_NAME" main
git subtree pull --prefix=. "$TEMPLATE_NAME" main --squash

git config --global user.name "Jenkins Automation"
git config --global user.email "jenkins@${ORG}.local"

git add .
if ! git diff --cached --quiet; then
    git commit -m "Sync changes from ${TEMPLATE_NAME}"
    git push "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${REPO}.git" HEAD:main || true
else
    echo "[INFO] No changes to commit after syncing template."
fi
