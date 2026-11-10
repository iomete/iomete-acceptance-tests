@lock=api
Feature: Secrets, written through each API and read back from where the platform keeps them

  The platform has three secret APIs over two stores. The deprecated v1 API keeps values in the
  environment's v1 store (a Kubernetes secret by default) and is the only one that hands a value
  back, so it is the one place a value can be checked end to end. The admin API writes admin-only
  and platform-wide (GLOBAL) secrets, and the domain v2 API lists GLOBAL ones next to its own,
  which is the handover a domain user relies on.

  Who may see a domain secret is covered in secret-visibility.feature. Key validation, conflicts
  and scope rules are iom-cluster's own logic and stay in its tests.

  Background:
    * url baseUrl
    * def v1Path = 'api/v1/domains/' + domain + '/secrets'
    * def v2Path = 'api/v2/domains/' + domain + '/secrets'
    * def adminPath = 'api/v1/admin/secrets'
    * def deleteSecret = function(path, scope){ karate.call('classpath:iomete/helpers/secret/delete-secret.feature', { secretPath: path, scope: scope }) }

  Scenario: a v1 secret's value is stored, replaced and removed
    * def secretKey = 'karate-secret-v1-' + runId
    # a repeat of `make test-one` keeps the run id, and a v1 POST of an existing key is refused
    # where the v1 store is the database
    * eval deleteSecret(v1Path + '/' + secretKey, null)
    * configure afterScenario = function(){ deleteSecret(v1Path + '/' + secretKey, null) }

    Given path v1Path
    And request { key: '#(secretKey)', value: 'karate-v1-value' }
    When method post
    Then status 200

    # the value comes back out of the store, not out of the write
    Given path v1Path, secretKey
    When method get
    Then status 200
    And match response == 'karate-v1-value'

    Given path v1Path
    When method get
    Then status 200
    And match response contains secretKey

    Given path v1Path
    And request { key: '#(secretKey)', value: 'karate-v1-value-updated' }
    When method put
    Then status 200

    Given path v1Path, secretKey
    When method get
    Then status 200
    And match response == 'karate-v1-value-updated'

    Given path v1Path, secretKey
    When method delete
    Then status 200

    Given path v1Path, secretKey
    When method get
    Then status 404

  Scenario: a GLOBAL admin secret reaches the domain listing, an ADMIN one does not
    * def globalKey = 'karate-secret-global-' + runId
    * def adminKey = 'karate-secret-admin-' + runId
    * eval deleteSecret(adminPath + '/' + globalKey, 'GLOBAL')
    * eval deleteSecret(adminPath + '/' + adminKey, 'ADMIN')
    * configure afterScenario =
      """
      function() {
        deleteSecret(adminPath + '/' + globalKey, 'GLOBAL');
        deleteSecret(adminPath + '/' + adminKey, 'ADMIN');
      }
      """

    Given path adminPath, globalKey
    And param scope = 'GLOBAL'
    And request { value: 'karate-global-value' }
    When method put
    Then status 200
    And match response == { key: '#(globalKey)', source: { type: 'KUBERNETES', id: 'global' } }

    Given path adminPath, adminKey
    And param scope = 'ADMIN'
    And request { value: 'karate-admin-value' }
    When method put
    Then status 200

    Given path adminPath
    And param scope = 'ADMIN'
    When method get
    Then status 200
    And match response[*].key contains adminKey
    And match response[*].key !contains globalKey

    # the domain's full listing (DOMAIN and GLOBAL) has the platform-wide secret, never the admin-only one
    Given path v2Path
    When method get
    Then status 200
    And match response[*].key contains globalKey
    And match response[*].key !contains adminKey
    * def entry = response.find(s => s.key == globalKey)
    And match entry.source.id == 'global'

    # removing it through the admin API takes it off the domain listing too
    Given path adminPath, globalKey
    And param scope = 'GLOBAL'
    When method delete
    Then status 200

    Given path v2Path
    And param scope = 'GLOBAL'
    When method get
    Then status 200
    And match response[*].key !contains globalKey

  Scenario: a v2 domain secret is listed for its domain and removed, whatever the domain-bundle setting
    # unlike secret-visibility.feature this needs no domain-level permission, so it runs with
    # domainBundleAuth off too, the default
    * def secretKey = 'karate-secret-v2-' + runId
    * eval deleteSecret(v2Path + '/' + secretKey, null)
    * configure afterScenario = function(){ deleteSecret(v2Path + '/' + secretKey, null) }

    Given path v2Path, secretKey
    And request { value: 'karate-v2-value' }
    When method put
    Then status 200
    And match response == { key: '#(secretKey)', source: { type: 'KUBERNETES', id: '#(domain)' } }

    Given path v2Path
    And param scope = 'DOMAIN'
    When method get
    Then status 200
    And match response[*].key contains secretKey

    Given path v2Path, secretKey
    When method delete
    Then status 200

    Given path v2Path
    And param scope = 'DOMAIN'
    When method get
    Then status 200
    And match response[*].key !contains secretKey
