@ignore
Feature: Wait until a webhook's latest delivery reads DELIVERED (helper).
  Usage: karate.call('classpath:iomete/helpers/webhook/wait-delivered.feature', { webhookId: '...' })
  Asks every 5s, for up to 3 minutes, until the latest delivery is DELIVERED or GAVE_UP (FAILED is
  retried by the platform, so it keeps waiting), and fails with the platform's error on GAVE_UP.

  Scenario: wait
    * configure retry = { count: 36, interval: 5000 }
    Given url baseUrl
    And path 'api/v1/domains', domain, 'webhooks', webhookId
    And retry until responseStatus == 200 && response.lastDelivery && (response.lastDelivery.status == 'DELIVERED' || response.lastDelivery.status == 'GAVE_UP')
    When method get
    Then status 200
    * def last = response.lastDelivery
    * if (last.status != 'DELIVERED') karate.fail('webhook ' + webhookId + ' gave up: ' + last.error)
