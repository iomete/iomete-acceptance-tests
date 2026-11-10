@ignore
Feature: Delete one model of a Model Gateway connection.
  Used by delete-connection.feature; a model that is already gone answers 404, which is done.

  Scenario: delete the model
    Given url baseUrl
    And path 'llm-gateway/v1/admin/connections', name, 'models', model
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404
