@ignore
Feature: Remove a domain tag alias by its alias, if it is still there (plumbing).
  Teardown helper, safe to call when the alias is already gone:
    karate.call('classpath:iomete/helpers/docker/delete-tag-alias.feature', { alias: 'my-alias' })

  Only the domain's own aliases are deleted; the platform-wide ones are read-only.

  Scenario: find the alias and delete it, or do nothing
    * def aliasesPath = 'api/v2/domains/' + domain + '/docker/tag-aliases'
    Given url baseUrl
    And path aliasesPath
    When method get
    Then status 200
    * def found = response.find(a => a.alias == alias && !a.isGlobal)
    * if (found == null) karate.abort()

    Given url baseUrl
    And path aliasesPath, found.id
    When method delete
    Then status 204
