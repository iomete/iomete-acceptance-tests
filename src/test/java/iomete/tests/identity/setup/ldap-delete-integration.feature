@ignore
Feature: Delete the LDAP integration. Admin action.
  Does nothing when there is none.
    karate.call('classpath:iomete/tests/identity/setup/ldap-delete-integration.feature')

  Scenario: delete
    Given url baseUrl
    And path 'api/v1/admin/identity/ldap-integration'
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404
