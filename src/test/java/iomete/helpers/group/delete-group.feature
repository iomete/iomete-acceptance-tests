@ignore
Feature: Delete a group by name.
  Cleanup helper for tests that created their own group — call it with:
    karate.call('classpath:iomete/helpers/group/delete-group.feature', { name: 'karate-test-group' })
  Does nothing if the group does not exist.

  Scenario: delete the group if it exists
    * def groupsPath = 'api/v1/admin/identity/groups'

    # look it up first so an already-gone group is a no-op rather than a 404 failure
    Given url baseUrl
    And path groupsPath, name
    When method get
    Then assert responseStatus == 200 || responseStatus == 404
    * if (responseStatus == 404) karate.abort()

    Given url baseUrl
    And path groupsPath, name
    When method delete
    Then status 204
