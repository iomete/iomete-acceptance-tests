@lock=api
Feature: Identity, a session's life through real auth — refresh and logout

  Three checks over the real auth endpoints that a faked identity provider could not answer
  for: a refresh token mints a working new access token, the same token with its signature
  altered is refused, and logout is accepted. A successful login is already covered by
  temp-password-login.feature, and API tokens by api-token-lifecycle.feature, so neither is
  repeated here.

  The refused token is the user's own refresh token with one character of its signature
  changed, so its subject, expiry, issuer and type are all genuine, and the call just before it
  shows the user can refresh. The 401 can therefore only come from the signature check. Both
  refresh calls go without the suite's credentials or cookies, as a client that is not signed
  in sends them.

  The user gets a fresh, non-temporary password first (generated per run, never committed):
  refresh refuses a user who still has to reset a temporary one. The login POST is done inline
  rather than through the shared login.feature helper, which only returns accessToken — this
  feature also needs refresh_token.

  Logout answers 204 and clears the session cookies, but the access token is a stateless JWT
  the API does not revoke, so it keeps working until it expires. Nothing asserts otherwise.

  Background:
    * url baseUrl
    * def username = 'karate-auth-session-user-' + runId
    * def password = 'Kt!' + java.util.UUID.randomUUID().toString()
    * def encode = function(value){ return java.net.URLEncoder.encode(value, 'UTF-8') }
    * def tokenPath = 'api/v1/identity/auth/token'

    # The same JWT with one character in the middle of its signature changed: still well formed
    # and the same length, but it no longer verifies against the header and body it carries.
    * def alterSignature =
      """
      function(jwt) {
        var dot = jwt.lastIndexOf('.');
        var signature = jwt.substring(dot + 1);
        var i = Math.floor(signature.length / 2);
        var swapped = signature.charAt(i) == 'A' ? 'B' : 'A';
        return jwt.substring(0, dot + 1) + signature.substring(0, i) + swapped + signature.substring(i + 1);
      }
      """

    # teardown first, so a setup step that fails half way still removes the user
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', { 'X-API-Token': token, Authorization: 'Bearer ' + token });
        karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: username });
      }
      """

    # delete first so each run starts from a known state
    * def cleared = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(username)' }
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(username)' }
    * def passwordSet = call read('classpath:iomete/helpers/user/set-password.feature') { username: '#(username)', password: '#(password)' }

    * def loginBody = 'username=' + encode(username) + '&password=' + encode(password) + '&grant_type=password&client_id=iomete'
    Given url baseUrl
    And path tokenPath
    And header Content-Type = 'application/x-www-form-urlencoded'
    And request loginBody
    When method post
    Then status 200
    * def loginResponse = response
    * match loginResponse.access_token == '#present'
    * match loginResponse.refresh_token == '#present'

  Scenario: a refresh token mints a working access token, and the same token with an altered signature is refused
    # no suite credentials or cookies, so the two refresh calls differ only in the token they carry
    * configure headers = null
    * configure cookies = null
    Given path 'api/v1/identity/auth/refresh'
    And request { refreshToken: '#(loginResponse.refresh_token)' }
    When method post
    Then status 200
    * def refreshed = response
    * match refreshed.accessToken == '#present'

    * def altered = alterSignature(loginResponse.refresh_token)
    * assert altered != loginResponse.refresh_token
    # the 200 above set session cookies; drop them so only the altered token is presented
    * configure cookies = null
    Given path 'api/v1/identity/auth/refresh'
    And request { refreshToken: '#(altered)' }
    When method post
    Then status 401

    * configure headers = { Authorization: '#("Bearer " + refreshed.accessToken)' }
    Given path 'api/v1/users', username
    When method get
    Then status 200
    And match response.item.username == username

  Scenario: logging out answers 204
    * configure headers = { Authorization: '#("Bearer " + loginResponse.access_token)' }
    Given path 'api/v1/identity/auth/logout'
    When method post
    Then status 204
