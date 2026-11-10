@lock=api
Feature: Git repositories, a GitHub repository can be browsed

  The SQL editor reads worksheets from GitHub too: a repository registered with a read credential
  lists its files. The rest of the Git flow is provider-agnostic and covered by git-repositories.feature.
  Skips unless IOMETE_GITHUB_REPO_URL and IOMETE_GITHUB_TOKEN are set, and on platforms before 4.0.2 (see AGENTS.md).

  Background:
    * url baseUrl
    * def env = function(name){ return java.lang.System.getenv(name) || null }
    * def repoUrl = env('IOMETE_GITHUB_REPO_URL')
    * def gitToken = env('IOMETE_GITHUB_TOKEN')
    * if (!repoUrl || !gitToken) karate.log('no test GitHub repository configured (IOMETE_GITHUB_REPO_URL, IOMETE_GITHUB_TOKEN), skipping')
    * if (!repoUrl || !gitToken) karate.abort()
    # GitHub repositories arrived in 4.0.2; builds from main count as newer
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates GitHub repositories, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()

    * if (!repoUrl.startsWith('https://')) karate.fail('IOMETE_GITHUB_REPO_URL must be an https URL of a GitHub repository, got ' + repoUrl)
    * def reposPath = 'api/v1/domains/' + domain + '/git/repositories'
    * def sqlGitPath = 'api/v1/domains/' + domain + '/sql/git'
    * def prefix = 'karate-github-' + runId + '-'
    * def clearFixtures = function(){ karate.call('classpath:iomete/tests/git/setup/clear-git-fixtures.feature', { prefix: prefix }) }

    # a repeat of `make test-one` keeps the run id, so it can meet its own leftovers
    * clearFixtures()
    * configure afterScenario = function(){ clearFixtures() }

  Scenario: a GitHub repository registered with a read credential lists its files
    Given path reposPath
    And request { name: '#(prefix + "repo")', provider: 'GITHUB', url: '#(repoUrl)', readCredential: '#(gitToken)' }
    When method post
    Then status 200
    * def repoId = response.id

    Given path sqlGitPath, repoId
    When method get
    Then status 200
    And match response.worksheets == '#[_ > 0]'
