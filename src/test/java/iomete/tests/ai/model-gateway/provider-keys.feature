@lock=api
Feature: Model Gateway provider keys, the admin API over the platform's secret store

  A provider key is the credential a Model Gateway connection uses to call an LLM provider.
  The gateway stores nothing itself: `/llm-gateway/v1/admin/provider-keys` hands the request
  to iom-cluster's cluster-scope secrets, as the caller. So what only the real platform can
  prove is that a key written here really lands in the secret store, that its value is never
  handed back, and that a delete removes it; and that the admin gate refuses callers without
  an admin role. The gateway's own handling (error relays, body forwarding, the unreachable
  platform) is covered by iom-ai-services' tests and stays out of here.

  The whole feature skips on platforms older than 4.0.2, which predate the Model Gateway (builds
  from main count as newer), and where the AI services are not enabled: `ai-services/version`
  answers 404 then. Where they are enabled, the gateway route has to work, so a 404 on it fails.

  Background:
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the Model Gateway, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()

    * url baseUrl

    # the AI services are optional
    * if (!aiServicesEnabled()) karate.log('AI services are not enabled on this target, skipping')
    * if (!aiServicesEnabled()) karate.abort()

    * def keysPath = 'llm-gateway/v1/admin/provider-keys'
    * def keyName = 'karate-provider-key-' + runId
    * def keyValue = 'karate-provider-key-value-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # teardown: back to admin first, since the failure that triggers this may have left the
    # scenario acting as a role-less user. A key that is already gone answers 404, which the helper treats as done;
    # any other failure fails the teardown
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        // run every delete, log each failure like the other teardowns, then fail once: a failed
        // delete must not hide behind a log line, and must not stop the ones after it either
        var failures = [];
        var steps = [
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: keyName }, what: 'provider key' }
        ];
        steps.forEach(function(step) {
          try {
            karate.call(step.feature, step.args);
          } catch (e) {
            karate.log(step.what + ' teardown failed:', e);
            failures.push(step.what + ': ' + e);
          }
        });
        if (failures.length > 0) throw 'teardown failed: ' + failures.join('; ');
      }
      """

    # the AI services are enabled, so the gateway route has to answer
    Given path keysPath
    When method get
    Then status 200

    # delete first: `make test-one` reuses the run id, so a killed attempt leaves its key behind
    # and this attempt's first POST would answer 409
    * def clearedKeyName = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(keyName)' }

  Scenario: a created key is listed without its value, updates in place, and a delete removes it
    # create: 201, and the answer names the key and where it is stored
    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201
    And match response.key == keyName
    And match response.source.type == 'KUBERNETES'
    And assert !karate.pretty(response).contains(keyValue)

    # listed, and the value is not part of what comes back
    Given path keysPath
    When method get
    Then status 200
    And match response[*].key contains keyName
    And assert !karate.pretty(response).contains(keyValue)

    # a PUT updates the value of the same key and leaves exactly one entry for it
    Given path keysPath, keyName
    And request { value: '#(keyValue + "-updated")' }
    When method put
    Then status 200
    And match response.key == keyName
    And assert !karate.pretty(response).contains(keyValue)

    Given path keysPath
    When method get
    Then status 200
    * def entries = response.filter(k => k.key == keyName)
    And match entries == '#[1]'

    # a delete takes it off the listing
    Given path keysPath, keyName
    When method delete
    Then status 200

    Given path keysPath
    When method get
    Then status 200
    And match response[*].key !contains keyName

  Scenario: the admin gate refuses a missing token and a role-less user, and lets a read-only admin read but not write
    * def outsider = 'karate-provider-key-outsider-' + runId
    * def reader = 'karate-provider-key-reader-' + runId
    * def deniedName = keyName + '-denied'
    * def clearedDeniedName = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(deniedName)' }
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        // run every delete, log each failure like the other teardowns, then fail once: a failed
        // delete must not hide behind a log line, and must not stop the ones after it either
        var failures = [];
        var steps = [
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: keyName }, what: 'provider key' },
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: deniedName }, what: 'denied key' },
          { feature: 'classpath:iomete/helpers/user/delete-user.feature', args: { username: outsider }, what: 'outsider user' },
          { feature: 'classpath:iomete/helpers/user/delete-user.feature', args: { username: reader }, what: 'reader user' }
        ];
        steps.forEach(function(step) {
          try {
            karate.call(step.feature, step.args);
          } catch (e) {
            karate.log(step.what + ' teardown failed:', e);
            failures.push(step.what + ': ' + e);
          }
        });
        if (failures.length > 0) throw 'teardown failed: ' + failures.join('; ');
      }
      """
    # delete first: a user left by an earlier attempt has no one-time password to log in with
    * def clearedOutsider = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(outsider)' }
    * def clearedReader = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(reader)' }
    * def createdOutsider = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(outsider)' }
    * match createdOutsider.temporaryPassword == '#notnull'
    * def createdReader = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(reader)' }
    * match createdReader.temporaryPassword == '#notnull'
    * def grantedReader = call read('classpath:iomete/helpers/user/add-roles.feature') { username: '#(reader)', roles: ['READ_ONLY_ADMIN'] }
    * def outsiderLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(outsider)', password: '#(createdOutsider.temporaryPassword)' }
    * def readerLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(reader)', password: '#(createdReader.temporaryPassword)' }

    # a key for the callers below to see, or fail to see
    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    # no credential at all
    * configure headers = {}
    Given path keysPath
    When method get
    Then status 401

    # a signed-in user with no admin role is refused, on a read and on a write
    * configure headers = { Authorization: '#("Bearer " + outsiderLogin.accessToken)' }
    Given path keysPath
    When method get
    Then status 403

    Given path keysPath
    And request { key: '#(deniedName)', value: '#(keyValue)' }
    When method post
    Then status 403

    # a read-only admin lists the keys, without their values, but cannot create one. A fresh grant
    # has to clear the role cache before the reader is let in, hence the retry
    * configure headers = { Authorization: '#("Bearer " + readerLogin.accessToken)' }
    * configure retry = { count: 12, interval: 5000 }
    Given path keysPath
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match response[*].key contains keyName
    And assert !karate.pretty(response).contains(keyValue)

    Given path keysPath
    And request { key: '#(deniedName)', value: '#(keyValue)' }
    When method post
    Then status 403

    # the refused creates stored nothing
    * configure headers = adminHeaders
    Given path keysPath
    When method get
    Then status 200
    And match response[*].key contains keyName
    And match response[*].key !contains deniedName
