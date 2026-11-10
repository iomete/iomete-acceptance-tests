@ignore
Feature: Turn on the webhookNotifications rollout flag and wait until webhooks answer (helper).
  Usage: karate.call('classpath:iomete/helpers/settings/enable-webhooks.feature')

  The flag is platform-wide and is left on. Services read flags through a short cache, so the
  domain's webhook list is asked again every 10s, for up to 3 minutes, until it stops answering 404.

  Scenario: set a global override and wait for it
    Given url baseUrl
    And path 'api/v1/admin/feature-flags/webhookNotifications/overrides'
    And request { scopeType: 'GLOBAL', enabled: true, notes: 'Turned on by the API test suite' }
    When method post
    Then status 200

    * configure retry = { count: 18, interval: 10000 }
    Given url baseUrl
    And path 'api/v1/domains', domain, 'webhooks'
    And retry until responseStatus != 404
    When method get
    Then status 200
