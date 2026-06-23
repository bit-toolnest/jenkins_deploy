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
                // Discover branches (but restrict to main only)
                gitHubBranchDiscovery {
                    strategyId(1) // build branch heads
                }
                headWildcardFilter {
                    includes("main")
                    excludes("*")
                }
                // Discover PRs from same repo, build merged with target branch
                gitHubPullRequestDiscovery {
                    strategyId(2)
                }
            }
        }
    }

    projectFactories {
            workflowMultiBranchProjectFactory {
                scriptPath("${JENKINSFILE_PATH}")
            }
        }


    orphanedItemStrategy {
        defaultOrphanedItemStrategy {
            pruneDeadBranches(true)
            daysToKeepStr("-1")
            numToKeepStr("20")   // keep last 20 builds per branch
            abortBuilds(false)
        }
    }

    // Enable triggers so Jenkins rescans and builds on push/PR events
    triggers {
        // Periodic rescan every 15 minutes
        periodicFolderTrigger {
            interval("900000")
        }
    }
}
