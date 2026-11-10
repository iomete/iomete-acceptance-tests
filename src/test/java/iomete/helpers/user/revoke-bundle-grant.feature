@ignore
Feature: Revoke one user's grant on one bundle (plumbing for revoke-bundle-grants.feature).
  404 means there was nothing to revoke.

  Scenario: delete the user's grant on the bundle
    Given url baseUrl
    And path 'api/v1/bundles', bundleId, 'permissions'
    And request { actorType: 'USER', actorId: '#(username)' }
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200 || responseStatus == 404
