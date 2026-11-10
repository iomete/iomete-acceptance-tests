@ignore
Feature: Get or create a classification tag by name. Admin action.
    karate.call('classpath:iomete/helpers/security/ensure-tag.feature', { tagName: n })
  Reuses a tag of that name, so a retry of the same run meets its own leftover. Returns:
    tagId  the tag's id

  Scenario: look the tag up by name, and create it when missing
    Given url baseUrl
    And path 'api/v1/admin/governance/classification-tags/name', tagName
    When method get
    Then assert responseStatus == 200 || responseStatus == 404
    * def tagId = responseStatus == 200 ? response.id : null
    * if (tagId) karate.abort()

    Given url baseUrl
    And path 'api/v1/admin/governance/classification-tags'
    And request { name: '#(tagName)', description: 'iomete-api-testing-suite: tag-based policy target' }
    When method post
    Then status 201
    * def tagId = response.id
