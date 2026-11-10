@ignore
Feature: Turn on the resourceGroupRoles rollout flag with a global override (helper).
  Called by enable-resource-group-roles.feature only. Setting it again is harmless.

  Scenario: set a global override
    Given url baseUrl
    And path 'api/v1/admin/feature-flags/resourceGroupRoles/overrides'
    And request { scopeType: 'GLOBAL', enabled: true, notes: 'Turned on by the API test suite' }
    When method post
    Then status 200
