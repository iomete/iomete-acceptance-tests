@lock=api
Feature: Identity, regenerating a token's secret replaces its value

  A regenerated token keeps its name, the new value authenticates and the old one is refused.

  Background:
    * if (!platformAtLeast('4.0.2')) { karate.log('token regeneration ships in 4.0.2+: skipping on ' + platformVersion); karate.abort() }
    * url baseUrl
    * def tokensPath = 'api/v1/auth/tokens'
    * def tokenName = 'karate-regen-token-' + runId
    * def probePath = 'api/v1/domains/' + domain + '/namespaces'
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    Given path tokensPath, tokenName
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404

    # teardown: never leave the token behind, pass or fail
    * configure afterScenario =
      """
      function() {
        var res = karate.http(baseUrl + '/' + tokensPath + '/' + tokenName).headers(adminHeaders).delete();
        if (res.status != 204 && res.status != 404) throw 'could not delete token ' + tokenName + ': HTTP ' + res.status;
      }
      """

  Scenario: the new secret authenticates and the old one is refused
    Given path tokensPath
    And request { name: '#(tokenName)' }
    When method post
    Then status 200
    * def oldSecret = response.token

    Given path tokensPath, tokenName, 'secret'
    When method post
    Then status 200
    * match response.name == tokenName
    * def newSecret = response.token
    * assert newSecret != oldSecret

    # still one token under that name, not a second one
    Given path tokensPath
    When method get
    Then status 200
    * assert response.items.filter(t => t.name == tokenName).length == 1

    * configure headers = { 'X-API-Token': '#(newSecret)', Authorization: '#("Bearer " + newSecret)' }
    Given path probePath
    When method get
    Then status 200

    # services cache a validated token for up to 30s each, so allow the change to land
    * configure headers = { 'X-API-Token': '#(oldSecret)', Authorization: '#("Bearer " + oldSecret)' }
    * configure retry = { count: 12, interval: 10000 }
    Given path probePath
    And retry until responseStatus == 401
    When method get

    * configure headers = { 'X-API-Token': '#(newSecret)', Authorization: '#("Bearer " + newSecret)' }
    Given path probePath
    When method get
    Then status 200
