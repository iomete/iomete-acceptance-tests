@ignore
Feature: Save the platform's email integration (helper).
  Usage: karate.call('classpath:iomete/helpers/mail/set-email-integration.feature', { emailConfig: {...} })

  The integration is platform-wide: every notification on the target is sent through it. Callers
  only set it where none exists, and never remove it.

  Scenario: save it
    Given url baseUrl
    And path 'api/v1/admin/integrations/email'
    And request emailConfig
    When method put
    Then status 204

    # Read it back: two runs saving at once could leave a row for another host on top.
    Given url baseUrl
    And path 'api/v1/admin/integrations/email'
    When method get
    Then status 200
    And match response.host == emailConfig.host
