@ignore
Feature: Delete a Model Gateway provider key by name.
  Cleanup helper for tests that created their own key — call it with:
    karate.call('classpath:iomete/helpers/ai/delete-provider-key.feature', { key: 'karate-provider-key-1' })
  Does nothing if the key does not exist.

  Scenario: delete the key if it exists
    # a key that is gone, or a gateway that is not routed, answers 404: nothing to remove
    Given url baseUrl
    And path 'llm-gateway/v1/admin/provider-keys', key
    When method delete
    Then assert responseStatus == 200 || responseStatus == 404
