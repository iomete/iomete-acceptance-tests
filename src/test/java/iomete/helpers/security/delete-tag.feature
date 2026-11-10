@ignore
Feature: Delete a classification tag by id. Admin action.
  The tag has to be off every column first (see tests/data-security/setup/policies/tag-column.feature).
    karate.call('classpath:iomete/helpers/security/delete-tag.feature', { tagId: t })
  Does nothing if the tag is already gone.

  Scenario: delete the tag
    Given url baseUrl
    And path 'api/v1/admin/governance/classification-tags', tagId
    When method delete
    Then assert responseStatus == 200 || responseStatus == 204 || responseStatus == 404
