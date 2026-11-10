@ignore
Feature: Disable and delete the platform's OIDC integration, only when it is this run's.
  Call with:
    karate.call('classpath:iomete/helpers/settings/delete-oidc-integration.feature')
  The integration is platform-wide, so this only removes one whose client is this run's
  (fixtures.oidcClient) and leaves any other alone. Returns removed: true when it deleted one.
  Disabling first takes the SSO button off the login page even if the delete fails.

  Scenario: disable and delete
    * def removed = false
    Given url baseUrl
    And path 'api/v1/admin/identity/oidc-integration'
    When method get
    Then status 200
    * if (response.item.settings.client.id != fixtures.oidcClient) karate.abort()

    Given path 'api/v1/admin/identity/oidc-integration', 'disable'
    And request {}
    When method put
    Then status 204

    Given path 'api/v1/admin/identity/oidc-integration'
    When method delete
    Then status 204
    * def removed = true
