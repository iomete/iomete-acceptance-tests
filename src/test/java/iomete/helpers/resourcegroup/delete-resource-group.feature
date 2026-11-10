@ignore
Feature: Archive (delete) a resource group by id, if it still exists (plumbing).
  Cleanup helper, safe to call when the group is already gone or was never created:
    karate.call('classpath:iomete/helpers/resourcegroup/delete-resource-group.feature', { groupId: groupId })
  A group with assets still in it cannot be archived (409), so callers that gave the group assets
  move or delete them first.

  Scenario: archive the group if it exists
    * if (!groupId) karate.abort()

    Given url baseUrl
    And path 'api/v1/resource-groups', groupId
    When method get
    Then assert responseStatus == 200 || responseStatus == 404
    * if (responseStatus == 404) karate.abort()

    Given url baseUrl
    And path 'api/v1/resource-groups', groupId
    When method delete
    Then status 204
