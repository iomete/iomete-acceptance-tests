@lock=api
Feature: Identity, an API token works until it is malformed or deleted

  One pass over a personal access token's life: it authenticates a real call, a tampered copy is
  refused, and once deleted it stops working.

  The iomt_ prefix and the masked list ship in 4.0.1. Older releases issue unprefixed tokens and
  list them in full, so those two checks only run from that version on.

  Assertions on the token value use assert rather than match, so a failure names the expression
  and never prints the secret into the report.

  Background:
    * url baseUrl
    # the user route, as the token helpers use: the domain-gated one also needs a bundle permission
    * def tokensPath = 'api/v1/auth/tokens'
    * def tokenName = 'karate-api-token-' + runId
    * def probePath = 'api/v1/domains/' + domain + '/namespaces'
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # the value is only returned on create, so drop a leftover of this name and mint a fresh one
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

  Scenario: a token authenticates, and is refused once malformed or deleted
    Given path tokensPath
    And request { name: '#(tokenName)' }
    When method post
    Then status 200
    * def secret = response.token
    * def newFormat = platformAtLeast('4.0.1')
    * if (!newFormat) karate.log('platform ' + platformVersion + ' predates iomt_ tokens: skipping the prefix and masking checks')
    * assert !newFormat || secret.startsWith('iomt_')

    # the list shows a masked form, never the value itself
    Given path tokensPath
    When method get
    Then status 200
    * def listed = response.items.find(t => t.name == tokenName)
    * match listed == '#notnull'
    * assert !newFormat || !karate.toString(response).contains(secret)
    # and the masked form keeps only a few characters, not most of the value
    * assert !newFormat || listed.token.length < secret.length / 2

    # the new token authenticates on its own, without the suite's admin token
    * configure headers = { 'X-API-Token': '#(secret)', Authorization: '#("Bearer " + secret)' }
    Given path probePath
    When method get
    Then status 200

    # one changed character is a different token, so it is refused
    * def last = secret.substring(secret.length - 1)
    * def malformed = secret.substring(0, secret.length - 1) + (last == 'a' ? 'b' : 'a')
    * configure headers = { 'X-API-Token': '#(malformed)', Authorization: '#("Bearer " + malformed)' }
    Given path probePath
    When method get
    Then status 401

    * configure headers = adminHeaders
    Given path tokensPath, tokenName
    When method delete
    Then status 204

    # services cache a validated token for up to 30s each, so allow the deletion time to land
    * configure headers = { 'X-API-Token': '#(secret)', Authorization: '#("Bearer " + secret)' }
    * configure retry = { count: 12, interval: 10000 }
    Given path probePath
    And retry until responseStatus == 401
    When method get
