@ignore
Feature: Remove a Docker registry by name, if it is still there (plumbing).
  Teardown helper, safe to call when the registry is already gone:
    karate.call('classpath:iomete/helpers/docker/delete-registry.feature', { name: 'my-registry' })

  Registries are platform-wide, so this only ever removes the one name it is given.

  Scenario: find the registry and delete it, or do nothing
    Given url baseUrl
    And path 'api/v1/admin/docker-registries'
    When method get
    Then status 200
    * def found = response.find(r => r.name == name)
    * if (found == null) karate.abort()

    Given url baseUrl
    And path 'api/v1/admin/docker-registries', found.id
    When method delete
    Then status 204
