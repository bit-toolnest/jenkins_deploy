#!/bin/bash
set -e

REPO="$1"
ORG="$2"
TEMPLATE_REPO="$3"

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

TEMPLATE_NAME=$(basename -s .git "$TEMPLATE_REPO")

echo "[INFO] Syncing changes from template: $TEMPLATE_NAME"
git fetch "$TEMPLATE_NAME" main

# Try subtree pull first
if ! git subtree pull --prefix=. "$TEMPLATE_NAME" main --squash; then
    echo "[WARN] Subtree pull failed, trying squash merge"
    if ! git merge --squash --allow-unrelated-histories "$TEMPLATE_NAME/main"; then
        echo "[ERROR] Merge failed, conflicts must be resolved"
        exit 1
    fi
fi

git config --global user.name "Jenkins Automation"
git config --global user.email "jenkins@${ORG}.local"

# Commit only if staged changes exist
if ! git diff --cached --quiet; then
    git commit -m "Sync changes from ${TEMPLATE_NAME}"
    if ! git push "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${REPO}.git" HEAD:main; then
        echo "[ERROR] Push failed"
        exit 1
    fi
    echo "[SUCCESS] Template synced and pushed"
else
    echo "[SUCCESS] No changes to commit"
fi
