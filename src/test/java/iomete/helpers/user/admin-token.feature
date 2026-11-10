@ignore
Feature: Mint the admin access token the whole suite runs as.
  Called once per run from karate-config.js when no token was supplied, so an environment
  that was just rebuilt needs no hand-pasted token. baseUrl is passed in because the config
  has not returned yet when this runs. Call it with:
    karate.callSingle('classpath:iomete/helpers/user/admin-token.feature',
                      { baseUrl: 'https://...', username: 'admin', password: '...' })
  Returns:
    accessToken  the admin access token

  Scenario: mint a token, then prove it authenticates and carries admin
    * def tokenName = karate.get('tokenName', 'karate-e2e-admin')
    * def minted = karate.call('classpath:iomete/helpers/user/get-access-token.feature', { baseUrl: baseUrl, username: username, password: password, tokenName: tokenName })
    * def accessToken = minted.accessToken

    # Preflight, so a wrong password or a non-admin user fails once here instead of turning
    # into a confusing 401/403 in every feature. Listing tokens needs an admin role, so a
    # 200 proves this token both authenticates and is admin.
    * configure headers = { 'X-API-Token': '#(accessToken)', Authorization: '#("Bearer " + accessToken)' }
    Given url baseUrl
    And path 'api/v1/auth/tokens'
    When method get
    Then status 200
