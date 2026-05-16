#!/bin/bash
set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_JAR="/var/cache/jenkins/war/WEB-INF/jenkins-cli.jar"
JENKINS_URL="http://localhost:8080"
JENKINSFILE_PATH_INPUT="Jenkinsfile"

CRED_FILE=${GITHUB_CRED_FILE:-"$SCRIPT_DIR/jenkins-creds.json"}
DSL_FILE="$SCRIPT_DIR/jobs.groovy"
SEED_JOB_XML="$SCRIPT_DIR/seed-job.xml"
CREDENTIALS_ID="github-creds"

# --- Install jq/xmlstarlet for credential parsing ---
if ! command -v jq >/dev/null 2>&1; then
  echo " jq not found. installing jq."
  install_pkg jq
fi

# --- Validate and parse credentials ---
if ! jq empty "$CRED_FILE" >/dev/null 2>&1; then
  echo "❌ Invalid JSON format in $CRED_FILE"
  exit 1
fi

JENKINS_USER_INPUT=$(jq -r '.jenkins_user // empty' "$CRED_FILE")
JENKINS_TOKEN_INPUT=$(jq -r '.jenkins_token // empty' "$CRED_FILE")
GITHUB_ORG_INPUT=$(jq -r '.github_org // empty' "$CRED_FILE")

SEED_JOB_NAME="${GITHUB_ORG_INPUT}-seed"

# --- CLI jar fallback ---
if [ ! -f "$CLI_JAR" ]; then
  CLI_JAR="$SCRIPT_DIR/jenkins-cli.jar"
  if [ ! -f "$CLI_JAR" ]; then
    echo "➡ Downloading jenkins-cli.jar..."
    wget -q "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -O "$CLI_JAR"
    echo "✅ jenkins-cli.jar downloaded"
  fi
fi

# --- Jenkins CLI auth ---
if [[ -n "$JENKINS_USER_INPUT" && -n "$JENKINS_TOKEN_INPUT" ]]; then
  JENKINS_USER="$JENKINS_USER_INPUT"
  JENKINS_PASS="$JENKINS_TOKEN_INPUT"
  echo "✅ Using Jenkins user/token from jenkins-creds.json"
else
  JENKINS_USER="admin"
  JENKINS_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
  echo "⚠️ Falling back to initialAdminPassword for Jenkins CLI auth"
fi

# --- Seed job XML ---
echo "ℹ️ Ensure the Job DSL plugin is installed in Jenkins before running this script."
DSL_CONTENT=$(sed \
    -e "s|\${GITHUB_ORG}|$GITHUB_ORG_INPUT|g" \
    -e "s|\${CREDENTIALS_ID}|$CREDENTIALS_ID|g" \
    -e "s|\${JENKINSFILE_PATH}|$JENKINSFILE_PATH_INPUT|g" \
    "$DSL_FILE")

cat > "$SEED_JOB_XML" <<EOF
<project>
  <actions/>
  <description>Seed job to run Job DSL</description>
  <builders>
    <javaposse.jobdsl.plugin.ExecuteDslScripts>
      <scriptText><![CDATA[
      $DSL_CONTENT
      ]]></scriptText>

      <usingScriptText>true</usingScriptText>
      <ignoreExisting>false</ignoreExisting>
      <removedJobAction>DELETE</removedJobAction>
      <removedViewAction>DELETE</removedViewAction>
      <lookupStrategy>JENKINS_ROOT</lookupStrategy>
    </javaposse.jobdsl.plugin.ExecuteDslScripts>
  </builders>
</project>
EOF

# --- Push or update seed job ---
if java -jar "$CLI_JAR" -s "$JENKINS_URL" -http \
     -auth "$JENKINS_USER:$JENKINS_PASS" list-jobs | grep -q "^$SEED_JOB_NAME$"; then
  echo "⏭ $SEED_JOB_NAME exists, updating"
  if ! java -jar "$CLI_JAR" -s "$JENKINS_URL" -http \
         -auth "$JENKINS_USER:$JENKINS_PASS" update-job "$SEED_JOB_NAME" < "$SEED_JOB_XML"; then
    echo "❌ Failed to update $SEED_JOB_NAME"
    exit 1
  fi
else
  echo "➡ Creating $SEED_JOB_NAME"
  if ! java -jar "$CLI_JAR" -s "$JENKINS_URL" -http \
         -auth "$JENKINS_USER:$JENKINS_PASS" create-job "$SEED_JOB_NAME" < "$SEED_JOB_XML"; then
    echo "❌ Failed to create $SEED_JOB_NAME"
    exit 1
  fi
fi

# --- Trigger seed job ---
if ! java -jar "$CLI_JAR" -s "$JENKINS_URL" -http \
       -auth "$JENKINS_USER:$JENKINS_PASS" \
       build "$SEED_JOB_NAME"; then
  echo "❌ Failed to run $SEED_JOB_NAME"
  exit 1
fi

echo "✅ Seed job executed, org-folder created"
