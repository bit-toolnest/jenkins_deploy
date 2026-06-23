pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Init Variables') {
            steps {
                script {
                    env.REMOTE_URL = sh(script: "git config --get remote.origin.url", returnStdout: true).trim()
                    env.ORG  = sh(script: "echo ${env.REMOTE_URL} | sed -E 's#https://github.com/([^/]+)/.*#\\1#'", returnStdout: true).trim()
                    env.REPO = sh(script: "echo ${env.REMOTE_URL} | sed -E 's#.*/([^/]+)\\.git#\\1#'", returnStdout: true).trim()
                    env.TEMPLATE_REPO = "https://github.com/bit-template/tool-template.git"
                }
            }
        }

        stage('Init Repo Protection') {
            when {
                expression { fileExists('.jenkins/first-run.flag') }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-creds',
                    usernameVariable: 'ADMIN_USER',
                    passwordVariable: 'GITHUB_TOKEN'
                )]) {
                    sh """
                        /opt/scripts/gradlew-permission.sh ${env.REPO} ${env.ORG}
			            ./gradlew linkTemplateRepo
                        /opt/scripts/remove-flag.sh ${env.REPO} ${env.ORG}
                        /opt/scripts/branch-protection.sh ${env.REPO} ${env.ORG}
                    """
                }
            }
        }

        stage('Sync Template') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-creds',
                    usernameVariable: 'ADMIN_USER',
                    passwordVariable: 'GITHUB_TOKEN'
                )]) {
                    sh "./gradlew syncTemplate"
                }
            }
        }

        stage('Sandbox Test') {
            steps {
                sh './gradlew testSandbox'
            }
        }
    }

    post {
        always {
            emailext(
                subject: "Jenkins Job: ${env.JOB_NAME} #${env.BUILD_NUMBER} finished",
                body: """\
Build Status: ${currentBuild.currentResult}
Repository: ${env.REPO}
Organization: ${env.ORG}
Template Repo: ${env.TEMPLATE_REPO}
Build URL: ${env.BUILD_URL}
""",
                to: "bitresearch2006@gmail.com"
            )
        }
    }
}
