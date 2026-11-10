@ignore
Feature: Obtain an access token for a user, usable to act AS that user.
  Logs in with username+password, then mints an access token (the same kind as IOMETE_TOKEN,
  sent via X-API-Token / Authorization Bearer). The user must have a known password
  (set-password.feature) and at least one admin role (minting a token needs AdminRole.ANY).
  Call it with:
    karate.call('classpath:iomete/helpers/user/get-access-token.feature',
                { username: 'karate-security-user', password: 'Karate123!@#' })
  Returns:
    accessToken  the access token string

  Scenario: login, then mint an access token as the user
    * def tokenName = karate.get('tokenName', 'karate-e2e')
    # baseUrl is passed explicitly so this works when called from karate-config.js too,
    # where there is no config to inherit it from yet
    * def login = call read('classpath:iomete/helpers/user/login.feature') { baseUrl: '#(baseUrl)', username: '#(username)', password: '#(password)' }
    * def jwt = login.accessToken

    # act as the user (bootstrap JWT) to manage its own tokens
    * configure headers = { Authorization: '#("Bearer " + jwt)' }

    # drop any existing token of this name (the secret can't be re-fetched), then create fresh
    Given url baseUrl
    And path 'api/v1/auth/tokens', tokenName
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404

    Given url baseUrl
    And path 'api/v1/auth/tokens'
    And request { name: '#(tokenName)' }
    When method post
    Then status 200
    * def accessToken = response.token
    * match accessToken == '#present'
