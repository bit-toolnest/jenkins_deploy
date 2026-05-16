
// GitHub Organization Folder job
organizationFolder("${GITHUB_ORG}-org") {

    description("GitHub Organization Folder for ${GITHUB_ORG} — scans all repos")

    displayName("${GITHUB_ORG} Organization")

    organizations {
        github {
            apiUri("https://api.github.com")
            repoOwner("${GITHUB_ORG}")
            credentialsId("${CREDENTIALS_ID}")

            traits {
                // Discover branches
                branchDiscovery {
                    strategyId(1)
                }
                // Discover PRs from same repo
                originPullRequestDiscovery {
                    strategyId(2)
                }
            }
        }
    }

    projectFactories {
        workflowBranchProjectFactory {
            scriptPath("${JENKINSFILE_PATH}")
        }
    }

    // Orphaned item strategy (clean up dead repos/branches)
    orphanedItemStrategy {
        defaultOrphanedItemStrategy {
            pruneDeadBranches(true)
            daysToKeepStr("-1")
            numToKeepStr("-1")
            abortBuilds(false)
        }
    }
}
