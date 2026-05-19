#!/bin/bash
set -e

REPO="$1"
ORG="$2"

# Jenkins injects these via withCredentials
ADMIN_USER="${ADMIN_USER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$ADMIN_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub credentials not available"
    exit 1
fi

STACK_FILE="stack.yml"

# Step 1: Update stack.yml
if [ -f "$STACK_FILE" ]; then
    echo "Replacing \$functionname with ${REPO} in stack.yml..."

    # Replace every occurrence of $functionname with the repo name
    sed -i "s|\$functionname|${REPO}|g" "$STACK_FILE"

    echo "stack.yml updated successfully."

    git config --global user.name "Jenkins Automation"
    git config --global user.email "jenkins@${ORG}.local"

    git add "$STACK_FILE"
    if ! git diff --cached --quiet; then
        git commit -m "Update stack.yml placeholders to ${REPO}"
    fi
else
    echo "Warning: stack.yml not found, skipping update."
fi

# Step 2: Remove first-run flag
if [ -f ".jenkins/first-run.flag" ]; then
    git rm .jenkins/first-run.flag || true
    git commit -m "Remove first-run flag after branch protection setup" || true
fi

# Push changes
git push https://${ADMIN_USER}:${GITHUB_TOKEN}@github.com/${ORG}/${REPO}.git HEAD:main || true

# Step 3: Apply branch protection
curl -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/${ORG}/${REPO}/branches/main/protection \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": ["continuous-integration/jenkins/pr-head"]
    },
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "dismiss_stale_reviews": true,
      "require_last_push_approval": true,
      "required_approving_review_count": 1
    },
    "restrictions": {
      "users": ["'"$ADMIN_USER"'"],
      "teams": []
    },
    "allow_force_pushes": false,
    "allow_deletions": false
  }'
