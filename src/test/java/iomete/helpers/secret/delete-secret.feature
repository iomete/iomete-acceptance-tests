@ignore
Feature: Remove a secret if it is still there (plumbing).
  Teardown helper, safe to call when the key is already gone:
    karate.call('classpath:iomete/helpers/secret/delete-secret.feature', { secretPath: 'api/v1/admin/secrets/my-key', scope: 'GLOBAL' })

  secretPath is the secret's own URL path under any of the secret APIs; scope is only sent when
  given (the admin API reads it). A missing key answers 404, which counts as done.

  Scenario: delete the key, or do nothing if it does not exist
    * def scope = karate.get('scope', null)
    Given url baseUrl
    And path secretPath
    And params scope == null ? {} : { scope: scope }
    When method delete
    Then assert responseStatus == 200 || responseStatus == 404
