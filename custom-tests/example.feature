@lock=api
Feature: Example of your own test

  Tests in this folder run with the IOMETE tests, and IOMETE releases never change them.
  This one creates a secret, checks it is listed, and removes it. Copy it as a starting point,
  or delete it.

  Background:
    # baseUrl, domain and runId come from the suite's settings
    * url baseUrl
    * def secretsPath = 'api/v2/domains/' + domain + '/secrets'
    # name everything with the run id, so overlapping runs never share an object
    * def secretKey = 'example-secret-' + runId
    # the suite's helpers can be called from here too
    * def deleteSecret = function(){ karate.call('classpath:iomete/helpers/secret/delete-secret.feature', { secretPath: secretsPath + '/' + secretKey }) }

  Scenario: a secret can be created, listed and removed
    # removes the secret even when a step below fails
    * configure afterScenario = deleteSecret

    Given path secretsPath, secretKey
    And request { value: 'example-value' }
    When method put
    Then status 200
    And match response.key == secretKey

    Given path secretsPath
    When method get
    Then status 200
    And match response[*].key contains secretKey

    Given path secretsPath, secretKey
    When method delete
    Then status 200

    Given path secretsPath
    When method get
    Then status 200
    And match response[*].key !contains secretKey
