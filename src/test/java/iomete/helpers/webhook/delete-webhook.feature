@ignore
Feature: Remove a domain webhook by name, if it is still there (plumbing).
  Usage: karate.call('classpath:iomete/helpers/webhook/delete-webhook.feature', { name: 'my-webhook' })
  Safe to call when the webhook is gone, and when webhooks are off (the list answers 404).

  Scenario: delete the webhook, or do nothing if it does not exist
    * def webhooksPath = 'api/v1/domains/' + domain + '/webhooks'
    Given url baseUrl
    And path webhooksPath
    When method get
    * if (responseStatus == 404) karate.abort()
    Then status 200
    * def found = response.items.filter(w => w.name == name)
    * if (found.length == 0) karate.abort()

    Given url baseUrl
    And path webhooksPath, found[0].id
    When method delete
    Then status 204
