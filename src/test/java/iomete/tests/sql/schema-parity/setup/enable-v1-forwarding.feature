@ignore
Feature: Turn on the schemaV1ForwardToV2 rollout flag and wait for services to pick it up (helper)
  Usage: karate.call('classpath:iomete/tests/sql/schema-parity/setup/enable-v1-forwarding.feature')

  Platform-wide and left on. iom-cluster refreshes its flags every minute and nothing on the V1
  routes tells forwarding apart from V1's own code, so this waits the cache out instead of polling.

  Scenario: set a global override and wait for it
    Given url baseUrl
    And path 'api/v1/admin/feature-flags/schemaV1ForwardToV2/overrides'
    And request { scopeType: 'GLOBAL', enabled: true, notes: 'Turned on by the API test suite' }
    When method post
    Then status 200
    * eval java.lang.Thread.sleep(70000)
