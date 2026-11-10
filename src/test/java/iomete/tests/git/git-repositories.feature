@lock=api
Feature: Git repositories, a GitLab repository can be browsed and checked out

  The SQL editor reads worksheets straight from GitLab. A repository registers with a read
  credential, then lists its files and branches, reads a file and checks out a branch, and both
  the credential and a linked token come back masked. A read credential GitLab refuses cannot
  register a repository.
  Skips unless IOMETE_GIT_REPO_URL and IOMETE_GIT_TOKEN are set (see AGENTS.md).

  Background:
    * url baseUrl
    * def env = function(name){ return java.lang.System.getenv(name) || null }
    * def repoUrl = env('IOMETE_GIT_REPO_URL')
    * def gitToken = env('IOMETE_GIT_TOKEN')
    * if (!repoUrl || !gitToken) karate.log('no test Git repository configured (IOMETE_GIT_REPO_URL, IOMETE_GIT_TOKEN), skipping')
    * if (!repoUrl || !gitToken) karate.abort()

    * def host = repoUrl.match(/^https?:\/\/[^\/]+/)
    * if (!host) karate.fail('IOMETE_GIT_REPO_URL must be an https URL of a GitLab project, got ' + repoUrl)
    * def gitlabUrl = host[0]
    * def reposPath = 'api/v1/domains/' + domain + '/git/repositories'
    * def sqlGitPath = 'api/v1/domains/' + domain + '/sql/git'
    * def tokensPath = 'api/v1/git/tokens'
    * def prefix = 'karate-git-' + runId + '-'
    * def clearFixtures = function(){ karate.call('classpath:iomete/tests/git/setup/clear-git-fixtures.feature', { prefix: prefix }) }

    # a repeat of `make test-one` keeps the run id, so it can meet its own leftovers
    * clearFixtures()
    * configure afterScenario = function(){ clearFixtures() }

  Scenario: a shared repository lists its files and branches and checks one out
    Given path tokensPath
    And request { name: '#(prefix + "token")', gitProvider: 'GITLAB', token: '#(gitToken)', url: '#(gitlabUrl)' }
    When method post
    Then status 200
    * def tokenId = response.id

    Given path reposPath
    And request { name: '#(prefix + "repo")', provider: 'GITLAB', url: '#(repoUrl)', readCredential: '#(gitToken)' }
    When method post
    Then status 200
    And match response.accessMode == 'SHARED'
    And match response.readCredentialConfigured == true
    * def repoId = response.id

    Given path sqlGitPath, repoId, 'tokens'
    And request { tokenId: '#(tokenId)' }
    When method put
    Then status 200

    Given path sqlGitPath, repoId
    When method get
    Then status 200
    And match response.token.token == '********'
    And match response.worksheets == '#[_ > 0]'
    * def defaultBranch = response.currentBranch
    * def worksheet = response.worksheets[0]

    # the listed path is already URL-encoded, so it goes on the url rather than through `path`
    Given url baseUrl + '/' + sqlGitPath + '/' + repoId + '/worksheets/' + worksheet.path
    When method get
    Then status 200
    And match response.content == '#string'
    * url baseUrl

    Given path sqlGitPath, repoId, 'branches'
    When method get
    Then status 200
    And match response contains defaultBranch
    # another branch when there is one, so the checkout actually moves
    * def branch = response.find(b => b != defaultBranch) || defaultBranch

    Given path sqlGitPath, repoId, 'branches', 'checkout'
    And request { branch: '#(branch)' }
    When method put
    Then status 200
    And match response.currentBranch == branch

  Scenario: a read credential GitLab refuses cannot register a repository
    # registering asks GitLab for the default branch with the credential, which fails on a bad one
    Given path reposPath
    And request { name: '#(prefix + "refused")', provider: 'GITLAB', url: '#(repoUrl)', readCredential: 'glpat-karate-invalid' }
    When method post
    Then status 400
    And match response.errorMessage contains 'The read credential cannot read'
