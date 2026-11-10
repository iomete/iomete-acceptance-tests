@ignore
Feature: Set a known, non-temporary password for a user (admin action).
  Needed before a test can log in AS that user. Call it with:
    karate.call('classpath:iomete/helpers/user/set-password.feature',
                { username: 'karate-security-user', password: 'Karate123!@#' })

  Scenario: reset the user's password to a known value
    Given url baseUrl
    And path 'api/v1/admin/identity/users', username, 'reset-password'
    And request { newPassword: '#(password)', confirmPassword: '#(password)', temporary: false }
    When method patch
    Then status 204
