@lock=api
Feature: Identity, an OIDC provider without a discovery document is configured by hand

  One main flow for SSO with an OIDC provider that publishes no discovery document: save the
  integration with its endpoints entered by hand, read them back, enable it, see the SSO overview
  count it as configured, and start a sign-in. The sign-in has to send the browser to the
  authorization endpoint entered here, with a state that matches the oidc-state cookie the
  callback checks it against.

  Nothing contacts the provider until the callback, so the endpoints are on a .invalid host and the
  client is a throwaway. The callback itself (code exchange, id_token checked against the JWKS, the
  dotted username claim) needs a provider that answers, and stays in iom-identity's tests.

  The OIDC integration is one platform-wide setting, so the feature only runs where platform
  changes are allowed, and never touches an integration it did not create. It skips where real SSO
  is set up, and fails in CI on one another run of this feature left, which would otherwise make
  every later run skip unnoticed. It removes its own afterwards, and make cleanup-run removes one a
  cancelled run left. While it is enabled, the login page shows a Sign in with SSO button; password
  sign-in keeps working.

  Background:
    # changes platform-wide state, so it runs only where the install allows that
    * if (!platformChangesAllowed()) karate.abort()
    * url baseUrl
    * def integrationPath = 'api/v1/admin/identity/oidc-integration'
    * def overviewPath = 'api/v1/admin/identity/sso-integrations'
    * def clientId = fixtures.oidcClient
    * def idp = 'https://idp-' + runId + '.karate.invalid'
    * def settings =
      """
      {
        idpUrl: '',
        client: { id: '#(clientId)', secret: '#("karate-" + java.util.UUID.randomUUID())' },
        scope: 'openid',
        endpoints: {
          authorizationEndpoint: '#(idp + "/grant-permission")',
          tokenEndpoint: '#(idp + "/oauth/token")',
          jwksUri: '#(idp + "/oauth/jwks")'
        },
        usernameClaim: 'user.pin',
        issuer: '#(idp)'
      }
      """
    * def inCi = java.lang.System.getenv('GITHUB_ACTIONS') == 'true'
    * def deletePath = 'classpath:iomete/helpers/settings/delete-oidc-integration.feature'
    # response header names arrive in whatever case the gateway sends
    * def headerValues = function(headers, name) { var key = Object.keys(headers).find(k => k.toLowerCase() == name); return key ? headers[key] : [] }

    # once a save was tried; the helper only ever removes an integration with this run's client
    * def saveTried = false
    * configure afterScenario = function() { if (saveTried) karate.call(deletePath) }

  Scenario: an integration with manual endpoints saves, counts as configured and starts a sign-in at its own authorization endpoint
    # an older platform drops the manual endpoints and saves nothing usable
    * if (!platformAtLeast('4.0.2-rc4')) karate.abort()

    # Step 1: the slot must be free. A leftover of this run (a retry, a make test-one repeat) is removed.
    # Anything else is never touched. Real SSO skips. Another run's is an overlap (rare, the scenario
    # takes under a second) or a leak a killed run left; a skip cannot tell those apart, so CI fails
    Given path integrationPath
    When method get
    Then status 200
    * def existing = response.item
    * def configured = existing.settings.idpUrl != '' || existing.settings.endpoints != null
    * def owner = configured ? existing.settings.client.id : null
    * if (owner == clientId) karate.call(deletePath)
    * if (configured && owner != clientId && owner.startsWith('karate-oidc-')) { var reason = 'another run left its OIDC integration (client ' + owner + '): remove it (DELETE ' + integrationPath + ') or run make cleanup-run for that run id'; if (inCi) karate.fail(reason); karate.log(reason + ', skipping'); karate.abort() }
    * if (configured && owner != clientId) { karate.log('this target has its own OIDC sign-in configured, which this feature never changes, skipping'); karate.abort() }
    # enabling OIDC is refused while SAML is enabled
    Given path overviewPath
    When method get
    Then status 200
    * if (response.default == 'SAML') { karate.log('SAML sign-in is enabled, so OIDC cannot be, skipping'); karate.abort() }

    # Step 2: save it with the endpoints by hand: no userinfo endpoint, so the user comes from the id_token,
    # verified against the JWKS, and the issuer is required. Marked first so a lost response is still removed
    * def saveTried = true
    Given path integrationPath
    And request { settings: '#(settings)' }
    When method post
    # another run took the free slot between our read and our save
    * if (responseStatus == 409) { karate.log('another OIDC integration was created between the check and the save, skipping'); karate.abort() }
    Then status 201
    * match response.settings contains { endpoints: '#(settings.endpoints)', usernameClaim: 'user.pin', issuer: '#(idp)' }

    # Step 3: read it back and enable it
    Given path integrationPath
    When method get
    Then status 200
    * match response.item.settings contains { idpUrl: '', endpoints: '#(settings.endpoints)', usernameClaim: 'user.pin', issuer: '#(idp)' }
    * match response.item.settings.client.id == clientId
    * match response.item.enabled == false

    Given path integrationPath, 'enable'
    And request {}
    When method put
    Then status 204

    # Step 4: the overview counts it as configured with no idpUrl, and as the default sign-in
    Given path overviewPath
    When method get
    Then status 200
    * match response.configured contains 'OIDC'
    * match response.default == 'OIDC'

    # Step 5: start a sign-in the way the login page does. No redirectUrl, so the cookie keeps the default landing page
    * configure followRedirects = false
    Given path 'api/v1/identity/auth/generate-oidc-url'
    When method get
    Then status 302

    # the browser goes to the authorization endpoint entered by hand, with this client and a fresh state
    * def location = headerValues(responseHeaders, 'location')[0]
    * assert location.startsWith(settings.endpoints.authorizationEndpoint + '?')
    * def query = {}
    * location.substring(location.indexOf('?') + 1).split('&').forEach(p => { var kv = p.split('='); query[decodeURIComponent(kv[0])] = decodeURIComponent(kv[1].replace(/\+/g, ' ')) })
    * match query contains { client_id: '#(clientId)', response_type: 'code', scope: 'openid', state: '#uuid' }
    * match query.redirect_uri == '#regex .*/api/v1/identity/auth/oidc/callback'

    # the state travels in the oidc-state cookie too (<state>.<landing page, base64url>), only to the callback's path
    * def setCookie = headerValues(responseHeaders, 'set-cookie').find(c => c.startsWith('oidc-state='))
    * match setCookie == '#string'
    * def cookieValue = setCookie.substring('oidc-state='.length, setCookie.indexOf(';'))
    * def parts = cookieValue.split('.')
    * match parts[0] == query.state
    * def landing = new java.lang.String(java.util.Base64.getUrlDecoder().decode(parts[1]), 'UTF-8')
    * match landing == '/compute'
    * def attributes = setCookie.toLowerCase()
    * match attributes contains 'path=/api/v1/identity/auth/oidc'
    * match attributes contains 'httponly'
    * match attributes contains 'secure'
    * match attributes contains 'samesite=lax'
