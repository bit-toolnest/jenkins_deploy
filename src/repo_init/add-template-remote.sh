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

echo "[INFO] Adding remote for template: $TEMPLATE_NAME"
git remote add "$TEMPLATE_NAME" "$TEMPLATE_REPO" || true

git config --global user.name "Jenkins Automation"
git config --global user.email "jenkins@${ORG}.local"

# Fetch template branch
git fetch "$TEMPLATE_NAME" main

# Try subtree add if not already linked
if ! git log | grep -q "subtree"; then
    echo "[INFO] Linking template with subtree add..."
    if ! git subtree add --prefix=. "$TEMPLATE_NAME" main --squash --allow-unrelated-histories; then
        echo "[WARN] Subtree add failed, falling back to squash merge"
        git merge --squash --allow-unrelated-histories "$TEMPLATE_NAME/main" || true
    fi
fi

# Commit only if changes are staged
if ! git diff --cached --quiet; then
    git commit -m "Link template remote: ${TEMPLATE_NAME}"
    git push "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${REPO}.git" HEAD:main || true
else
    echo "[INFO] No changes to commit after linking template."
fi
