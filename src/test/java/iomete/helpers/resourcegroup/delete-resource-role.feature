@ignore
Feature: Delete a custom resource role by name, if it still exists (plumbing).
  Cleanup helper, safe to call when the role is already gone or was never created:
    karate.call('classpath:iomete/helpers/resourcegroup/delete-resource-role.feature', { roleName: 'karate-rr-x' })
  A built-in role (Reader/Contributor/Owner) cannot be deleted; this only ever targets custom ones.

  Scenario: delete the role if it exists
    * def rolesPath = 'api/v1/domains/' + domain + '/resource-roles'

    Given url baseUrl
    And path rolesPath, roleName
    When method get
    Then assert responseStatus == 200 || responseStatus == 404
    * if (responseStatus == 404) karate.abort()

    Given url baseUrl
    And path rolesPath, roleName
    When method delete
    Then status 204
