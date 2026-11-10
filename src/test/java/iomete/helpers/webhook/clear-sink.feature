@ignore
Feature: Delete the webhook requests the test sink received on one channel (helper).
  Usage: karate.call('classpath:iomete/helpers/webhook/clear-sink.feature', { channel: '...' })

  Scenario: delete
    * def login = karate.callSingle('classpath:iomete/helpers/webhook/sink-login.feature')
    * configure headers = { Authorization: '#(login.basic)' }
    Given url login.sinkUrl
    And path 'api/hooks', channel
    When method delete
    Then status 204
