@ignore
Feature: Password login as a data-plane user; returns a Bearer access token.
  Lets tests act AS a specific user (the SQL APIs derive identity from this token). Call with:
    karate.call('classpath:iomete/helpers/user/login.feature',
                { username: 'karate-security-user', password: 'Karate123!@#' })
  Works with a password set by set-password.feature and with the temporary password minted by
  create-user.feature. Returns:
    accessToken  the Bearer JWT (sub = username)

  Scenario: exchange username + password for an access token
    # encode the values: generated passwords contain '=' and '+', which would otherwise be
    # read as form delimiters and yield a 401
    * def encode = function(value){ return java.net.URLEncoder.encode(value, 'UTF-8') }
    * def body = 'username=' + encode(username) + '&password=' + encode(password) + '&grant_type=password&client_id=iomete'
    Given url baseUrl
    And path 'api/v1/identity/auth/token'
    And header Content-Type = 'application/x-www-form-urlencoded'
    And request body
    When method post
    Then status 200
    * def accessToken = response.access_token
    * match accessToken == '#present'
