@lock=api
Feature: Identity, service account and domain access tokens work until deleted

  The same lifecycle as a personal token, through the service-account and the domain routes:
  create, list, update, authenticate with it, delete, and the deleted token stops working.

  Background:
    * url baseUrl
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    * def asToken = function(secret){ return { 'X-API-Token': secret, Authorization: 'Bearer ' + secret } }
    * def tokenName = 'karate-token-' + runId

  Scenario: a service account token works until it is deleted
    * if (!platformAtLeast('4.0.2')) { karate.log('service-account ownership ships in 4.0.2+: skipping on ' + platformVersion); karate.abort() }
    * def sa = 'karate-token-sa-' + runId
    * def tokensPath = 'api/v1/auth/service-accounts/' + sa + '/tokens'

    # teardown: back to admin, since the failure may have left the scenario acting as the token
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var res = karate.http(baseUrl + '/' + tokensPath + '/' + tokenName).headers(adminHeaders).delete();
        karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: sa });
        if (res.status != 204 && res.status != 404) throw 'could not delete token ' + tokenName + ': HTTP ' + res.status;
      }
      """

    * def createdSa = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(sa)', type: 'SERVICE_ACCOUNT' }

    # only an owner may manage a service account's tokens, so make the suite's user one
    Given path 'api/v1/user'
    When method get
    Then status 200
    * def me = response.username

    Given path 'api/v1/service-accounts', sa, 'owners/users'
    And request [ '#(me)' ]
    When method post
    Then status 204

    # the value is only returned on create, so drop a leftover of this name first
    Given path tokensPath, tokenName
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404

    Given path tokensPath
    And request { name: '#(tokenName)' }
    When method post
    Then status 200
    * def secret = response.token

    Given path tokensPath
    When method get
    Then status 200
    And match response.items[*].name contains tokenName

    Given path tokensPath, tokenName
    And request { maxRps: 5 }
    When method patch
    Then status 200
    And match response.maxRps == 5

    # the token authenticates as the service account
    * configure headers = asToken(secret)
    Given path 'api/v1/user'
    When method get
    Then status 200
    And match response.username == sa

    * configure headers = adminHeaders
    Given path tokensPath, tokenName
    When method delete
    Then status 204

    # services cache a validated token for up to 30s each, so allow the deletion time to land
    * configure headers = asToken(secret)
    * configure retry = { count: 12, interval: 10000 }
    Given path 'api/v1/user'
    And retry until responseStatus == 401
    When method get

  Scenario: a domain token works until it is deleted
    # with domain bundles on, this route also needs a bundle grant the suite's user may not have
    * if (domainBundleAuth) { karate.log('domain bundle authorization is on: skipping the domain token route'); karate.abort() }
    * def tokensPath = 'api/v1/domains/' + domain + '/auth/tokens'
    * def probePath = 'api/v1/domains/' + domain + '/namespaces'

    * configure afterScenario =
      """
      function() {
        var res = karate.http(baseUrl + '/' + tokensPath + '/' + tokenName).headers(adminHeaders).delete();
        if (res.status != 204 && res.status != 404) throw 'could not delete token ' + tokenName + ': HTTP ' + res.status;
      }
      """

    Given path tokensPath, tokenName
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404

    Given path tokensPath
    And request { name: '#(tokenName)' }
    When method post
    Then status 200
    * def secret = response.token

    Given path tokensPath
    When method get
    Then status 200
    And match response.items[*].name contains tokenName

    Given path tokensPath, tokenName
    And request { maxRps: 5 }
    When method patch
    Then status 200
    And match response.maxRps == 5

    * configure headers = asToken(secret)
    Given path probePath
    When method get
    Then status 200

    * configure headers = adminHeaders
    Given path tokensPath, tokenName
    When method delete
    Then status 204

    * configure headers = asToken(secret)
    * configure retry = { count: 12, interval: 10000 }
    Given path probePath
    And retry until responseStatus == 401
    When method get
