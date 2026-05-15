#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_JAR="/var/cache/jenkins/war/WEB-INF/jenkins-cli.jar"
JENKINS_URL="http://localhost:8080"
JENKINSFILE_PATH_INPUT="Jenkinsfile"


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
CRED_FILE=${GITHUB_CRED_FILE:-"$SCRIPT_DIR/user-creds.json"}
JENKINS_USER_INPUT=$(jq -r '.jenkins_user // empty' "$CRED_FILE")
JENKINS_TOKEN_INPUT=$(jq -r '.jenkins_token // empty' "$CRED_FILE")
GITHUB_ORG_INPUT=$(jq -r '.org // empty' "$CRED_FILE")

if [[ -n "$JENKINS_USER_INPUT" && -n "$JENKINS_TOKEN_INPUT" ]]; then
  JENKINS_USER="$JENKINS_USER_INPUT"
  JENKINS_PASS="$JENKINS_TOKEN_INPUT"
  echo "✅ Using Jenkins user/token from user-creds.json"
else
  JENKINS_USER="admin"
  JENKINS_PASS=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
  echo "⚠️ Falling back to initialAdminPassword for Jenkins CLI auth"
fi

# --- Seed job XML ---
DSL_FILE="$SCRIPT_DIR/jobs.groovy"

sed "s|\${GITHUB_ORG}|$GITHUB_ORG_INPUT|g; \
     s|\${CREDENTIALS_ID}|github-creds|g; \
     s|\${JENKINSFILE_PATH}|$JENKINSFILE_PATH_INPUT|g" \
     "$DSL_FILE" | sudo tee /var/lib/jenkins/jobs.groovy >/dev/null

sudo chown jenkins:jenkins /var/lib/jenkins/jobs.groovy

SEED_JOB_XML="$SCRIPT_DIR/seed-job.xml"
cat > "$SEED_JOB_XML" <<EOF
<project>
  <actions/>
  <description>Seed job to run Job DSL</description>
  <builders>
    <javaposse.jobdsl.plugin.ExecuteDslScripts>
      <targets>/var/lib/jenkins/jobs.groovy</targets>
      <usingScriptText>false</usingScriptText>
      <ignoreExisting>false</ignoreExisting>
      <removedJobAction>DELETE</removedJobAction>
      <removedViewAction>DELETE</removedViewAction>
      <lookupStrategy>JENKINS_ROOT</lookupStrategy>
    </javaposse.jobdsl.plugin.ExecuteDslScripts>
  </builders>
</project>
EOF


# --- Push seed job ---
if ! java -jar "$CLI_JAR" -s "$JENKINS_URL" -http \
       -auth "$JENKINS_USER:$JENKINS_PASS" \
       create-job seed-job < "$SEED_JOB_XML"; then
  echo "❌ Failed to create seed job"
  exit 1
fi

# --- Trigger seed job ---
if ! java -jar "$CLI_JAR" -s "$JENKINS_URL" -http \
       -auth "$JENKINS_USER:$JENKINS_PASS" \
       build seed-job; then
  echo "❌ Failed to run seed job"
  exit 1
fi

echo "✅ Seed job executed, org-folder created"
