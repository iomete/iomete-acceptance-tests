@ignore
Feature: Subscribe a webhook to a job's failures (helper).
  Usage: karate.call('classpath:iomete/helpers/webhook/subscribe-job.feature', { jobId: '...', webhookId: '...' })

  Scenario: subscribe On Failure
    Given url baseUrl
    And path 'api/v1/domains', domain, 'notification-settings', 'resource', jobId
    And request { recipient: '#(webhookId)', eventTypes: ['FAILED'], channel: 'WEBHOOK' }
    When method post
    Then status 204
