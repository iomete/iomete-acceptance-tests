@ignore
Feature: Delete a data-plane user by username.
  Cleanup helper for tests that created their own user — call it with:
    karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: 'karate-test-user' })
  Does nothing if the user does not exist.

  Scenario: delete the user if it exists
    * def username = username.toLowerCase()
    * def usersPath = 'api/v1/admin/identity/users'

    # look it up first so an already-gone user is a no-op rather than a 404 failure
    Given url baseUrl
    And path usersPath, username
    When method get
    Then assert responseStatus == 200 || responseStatus == 404
    * if (responseStatus == 404) karate.abort()

    Given url baseUrl
    And path usersPath, username
    When method delete
    Then status 204
