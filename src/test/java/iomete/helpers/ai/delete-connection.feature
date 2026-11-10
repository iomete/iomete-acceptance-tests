@ignore
Feature: Delete a Model Gateway connection by name, models first.
  Cleanup helper for tests that created their own connection — call it with:
    karate.call('classpath:iomete/helpers/ai/delete-connection.feature', { name: 'karate-conn-1' })
  Does nothing if the connection does not exist. A connection that still has models is refused
  (409 connection_in_use), so its models are removed first.

  Scenario: delete the connection and its models if they exist
    Given url baseUrl
    And path 'llm-gateway/v1/admin/connections', name
    When method get
    # a connection that is gone, or a gateway that is not routed, answers 404: nothing to remove
    * if (responseStatus == 404) karate.abort()
    Then status 200
    * def modelNames = karate.map(response.models, m => m.name)

    * def removeModel =
      """
      function(modelName) {
        var r = karate.call('classpath:iomete/helpers/ai/delete-connection-model.feature', { name: name, model: modelName });
        return r;
      }
      """
    * karate.forEach(modelNames, removeModel)

    Given url baseUrl
    And path 'llm-gateway/v1/admin/connections', name
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404
