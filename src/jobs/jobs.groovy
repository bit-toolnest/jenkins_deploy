organizationFolder("${GITHUB_ORG}-org") {

    description("GitHub Organization Folder for ${GITHUB_ORG} — scans all repos")
    displayName("${GITHUB_ORG} Organization")

    organizations {
        github {
            apiUri("https://api.github.com")
            repoOwner("${GITHUB_ORG}")
            credentialsId("${CREDENTIALS_ID}")

            traits {
                // Discover branch heads (main only)
                gitHubBranchDiscovery {
                    strategyId(1) // maps to BranchDiscoveryTrait(strategyId=1)
                }

                // Restrict branch discovery to main
              //  headWildcardFilter {
              //      includes("main")
              //      excludes("") 
              //  }

                // Discover PRs from origin, build merged with target branch
                gitHubPullRequestDiscovery {
                    strategyId(1) // maps to OriginPullRequestDiscoveryTrait(strategyId=1)
                }
            }
        }
    }

    projectFactories {
        configure { node ->
            def wfFactory = node.appendNode(
                'org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory'
            )
            wfFactory.appendNode('scriptPath', "${JENKINSFILE_PATH}")
        }
    }    

    orphanedItemStrategy {
        defaultOrphanedItemStrategy {
            pruneDeadBranches(true)
            daysToKeepStr("-1")
            numToKeepStr("20")
            abortBuilds(false)
        }
    }

    triggers {
        periodicFolderTrigger {
            interval("1d") // 1 day
        }
    }

}
