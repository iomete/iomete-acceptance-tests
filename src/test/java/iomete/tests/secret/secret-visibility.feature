@lock=api
Feature: Secrets, who can see a domain secret and what a delete removes

  Secrets hold customer credentials, so the question worth asking of the real platform is
  who is allowed to see them. The value itself is never handed back, only the key and where
  it came from, so these scenarios follow the key: a user granted the permission sees it and
  keeps seeing it after the value changes, a user without the grant is refused outright, and
  a delete takes it off the listing.

  Vault-backed secrets are left out: they need a reachable Vault and its credentials, which
  this environment does not provide.

  The permitted user is polled rather than checked once, because a fresh grant has to clear
  the identity permission cache before it takes effect.

  Both scenarios turn on a domain-level permission, so they only mean anything where domain
  bundles do: with `domainBundleAuth` off there is nothing to grant LIST_SECRETS on and
  nothing enforcing it, and they self-skip.

  Background:
    * if (!domainBundleAuth) karate.abort()

    * url baseUrl
    * def secretsPath = 'api/v2/domains/' + domain + '/secrets'
    * def secretKey = 'karate-secret-visibility-' + runId
    * def reader = 'karate-secret-reader-' + runId
    * def outsider = 'karate-secret-outsider-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # delete first: the one-time password comes back only from a real create, not from a
    # reuse, so a user left behind by an earlier run would leave nothing to log in with
    * def clearedReader = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(reader)' }
    * def clearedOutsider = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(outsider)' }

    # pass or fail, as admin: the scenarios switch to the users' tokens
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var steps = [
          () => karate.call('classpath:iomete/helpers/secret/delete-secret.feature', { secretPath: secretsPath + '/' + secretKey }),
          // deleting a user leaves its grant on the domain's root bundle
          () => { var granted = karate.get('granted'); if (granted && granted.rootBundleId) karate.call('classpath:iomete/helpers/user/revoke-bundle-grant.feature', { bundleId: granted.rootBundleId, username: reader }) },
          () => karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: reader }),
          () => karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: outsider })
        ];
        // run every step, then fail once, so a leftover never hides behind a log line
        var failures = [];
        steps.forEach(step => { try { step() } catch (e) { karate.log('teardown step failed:', e); failures.push('' + e) } });
        if (failures.length > 0) throw 'teardown failed: ' + failures.join('; ');
      }
      """

  Scenario: a permitted user sees the secret across an update, and stops seeing it once deleted
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(reader)' }
    * match created.temporaryPassword == '#notnull'
    * def granted = call read('classpath:iomete/helpers/domain/grant-domain-permissions.feature') { username: '#(reader)', permissions: ['LIST_SECRETS'] }
    * def login = call read('classpath:iomete/helpers/user/login.feature') { username: '#(reader)', password: '#(created.temporaryPassword)' }

    # admin writes the secret
    Given path secretsPath, secretKey
    And request { value: 'karate-secret-value' }
    When method put
    Then status 200

    # the reader sees its key, once the grant has propagated
    * configure headers = { Authorization: '#("Bearer " + login.accessToken)' }
    * configure retry = { count: 20, interval: 5000 }
    Given path secretsPath
    And param scope = 'DOMAIN'
    And retry until responseStatus == 200 && response.find(s => s.key == secretKey) != null
    When method get
    Then status 200
    And match response[*].key contains secretKey
    * def entry = response.find(s => s.key == secretKey)
    And match entry.source.type == 'KUBERNETES'

    # changing the value leaves the key listed
    * configure headers = adminHeaders
    Given path secretsPath, secretKey
    And request { value: 'karate-secret-value-updated' }
    When method put
    Then status 200

    * configure headers = { Authorization: '#("Bearer " + login.accessToken)' }
    Given path secretsPath
    And param scope = 'DOMAIN'
    When method get
    Then status 200
    And match response[*].key contains secretKey

    # deleting it takes the key off the listing
    * configure headers = adminHeaders
    Given path secretsPath, secretKey
    When method delete
    Then status 200

    * configure headers = { Authorization: '#("Bearer " + login.accessToken)' }
    * configure retry = { count: 15, interval: 5000 }
    Given path secretsPath
    And param scope = 'DOMAIN'
    And retry until responseStatus == 200 && response.find(s => s.key == secretKey) == null
    When method get
    Then status 200
    And match response[*].key !contains secretKey

  Scenario: a user without the permission is refused the listing
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(outsider)' }
    * match created.temporaryPassword == '#notnull'
    * def login = call read('classpath:iomete/helpers/user/login.feature') { username: '#(outsider)', password: '#(created.temporaryPassword)' }

    * configure headers = { Authorization: '#("Bearer " + login.accessToken)' }
    Given path secretsPath
    And param scope = 'DOMAIN'
    When method get
    Then status 403
