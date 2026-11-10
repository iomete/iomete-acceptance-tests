@ignore
Feature: Delete the test mail sink's messages to one recipient (helper).
  Usage: karate.call('classpath:iomete/helpers/mail/clear-mailbox.feature', { recipient: '...' })

  Scenario: delete
    * def login = karate.callSingle('classpath:iomete/helpers/mail/sink-login.feature')
    * configure headers = { Authorization: '#(login.basic)' }
    Given url login.sinkUrl
    And path 'api/v1/search'
    And param query = 'to:"' + recipient + '"'
    When method delete
    Then status 200
