Feature: Revoke the admin token this run minted, the run's auth teardown.

  Token names carry the run id so concurrent runs don't revoke each other's, which means a
  finished run leaves its own token behind unless it removes it. Deriving the name from the
  same runId the config used, rather than listing and matching, keeps this run from touching
  a token another run is still using.

  Called from `ApiTest.revokeRunToken()` via JUnit's @AfterAll, so it runs in the same JVM that
  minted the token and reads the run id straight out of the config. Never scanned, since
  helpers/ sits outside iomete/tests.

  Scenario: revoke this run's token
    * def tokenName = 'karate-e2e-admin-' + runId

    # 404 is fine: an explicit IOMETE_TOKEN means nothing was minted under this name
    Given url baseUrl
    And path 'api/v1/auth/tokens', tokenName
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404

    * eval java.lang.System.out.println('revoked token ' + tokenName + ' (status ' + responseStatus + ')')
