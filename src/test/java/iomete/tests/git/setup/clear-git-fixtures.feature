@ignore
Feature: Delete the Git repositories and the admin's Git tokens whose names start with a prefix. Admin action.
    karate.call('classpath:iomete/tests/git/setup/clear-git-fixtures.feature', { prefix: p })
  End the prefix with a separator, or it also matches longer run ids.

  Scenario: delete both
    * def reposPath = 'api/v1/domains/' + domain + '/git/repositories'
    * def remove = function(p){ karate.call('classpath:iomete/tests/git/setup/delete-git-fixture.feature', { fixturePath: p }) }

    Given url baseUrl
    And path reposPath
    When method get
    Then status 200
    * response.filter(r => r.name.startsWith(prefix)).forEach(r => remove(reposPath + '/' + r.id))

    Given url baseUrl
    And path 'api/v1/git/tokens'
    When method get
    Then status 200
    * response.filter(t => t.name.startsWith(prefix)).forEach(t => remove('api/v1/git/tokens/' + t.id))
