@ignore
Feature: Delete one Git repository or Git token by its API path. Admin action.
    karate.call('classpath:iomete/tests/git/setup/delete-git-fixture.feature', { fixturePath: 'api/v1/git/tokens/<id>' })
  Does nothing when it is already gone.

  Scenario: delete
    Given url baseUrl
    And path fixturePath
    When method delete
    Then assert responseStatus == 200 || responseStatus == 204 || responseStatus == 404
