#!/bin/bash
set -euo pipefail

REPO="$1"
ORG="$2"
TEMPLATE_REPO="$3"

ADMIN_USER="${ADMIN_USER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ $# -ne 3 ]; then
    echo "Usage: $0 <repo> <org> <template-repo-url>"
    exit 1
fi

if [[ -z "$ADMIN_USER" || -z "$GITHUB_TOKEN" ]]; then
    echo "[ERROR] ADMIN_USER and GITHUB_TOKEN environment variables are required."
    exit 1
fi

TEMPLATE_NAME=$(basename -s .git "$TEMPLATE_REPO")
IGNORE_FILE=".templateignore"

git config --global user.name "Jenkins Automation"
git config --global user.email "jenkins@${ORG}.local"

echo "[INFO] =================================================="
echo "[INFO] Template Synchronization"
echo "[INFO] Repository : ${REPO}"
echo "[INFO] Template   : ${TEMPLATE_NAME}"
echo "[INFO] =================================================="

#
# Ensure remote exists
#
echo "[INFO] Configuring template remote..."

if git remote get-url "$TEMPLATE_NAME" >/dev/null 2>&1; then
    git remote set-url "$TEMPLATE_NAME" "$TEMPLATE_REPO"
else
    git remote add "$TEMPLATE_NAME" "$TEMPLATE_REPO"
fi

#
# Fetch latest template
#
echo "[INFO] Fetching template..."
git fetch "$TEMPLATE_NAME"

#
# Save current HEAD
#
PRE_MERGE_HEAD=$(git rev-parse HEAD)

#
# Merge (squash to avoid auto commit)
#
echo "[INFO] Merging template with squash..."

if ! git merge --squash -X theirs "${TEMPLATE_NAME}/main"; then
    echo "[INFO] Normal squash merge failed."
    echo "[INFO] Retrying with --allow-unrelated-histories..."
    if ! git merge --squash --allow-unrelated-histories -X theirs "${TEMPLATE_NAME}/main"; then
        echo "[ERROR] Merge failed."
        echo "[ERROR] Manual conflict resolution required."
        exit 1
    fi
fi

#
# Restore repository specific files BEFORE commit
#
if [[ -f "$IGNORE_FILE" ]]; then
    echo "[INFO] Restoring repository-specific paths..."
    while IFS= read -r path || [[ -n "$path" ]]; do
        path="$(echo "$path" | xargs)"
        [[ -z "$path" || "$path" =~ ^# ]] && continue
        if git cat-file -e "${PRE_MERGE_HEAD}:${path}" 2>/dev/null; then
            echo "  -> ${path}"
            git restore --source="${PRE_MERGE_HEAD}" -- "${path}"
        fi
    done < "$IGNORE_FILE"
fi

#
# Stage all changes
#
git add .

#
# Nothing changed?
#
if git diff --cached --quiet; then
    echo "[SUCCESS] Repository already up-to-date."
    exit 0
fi

#
# Commit (single commit with template changes minus ignores)
#
echo "[INFO] Creating commit..."
git commit -m "Sync template: ${TEMPLATE_NAME}"


#
# Push
#
echo "[INFO] Pushing changes..."

git push \
    "https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${REPO}.git" \
    HEAD:main

echo "[SUCCESS] Template synchronized successfully."
