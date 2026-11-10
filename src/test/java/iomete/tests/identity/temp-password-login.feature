@lock=api
Feature: Identity, a new user logs in with the temporary password it was issued

  One end-to-end happy path over real auth: creating a user mints a one-time password, that
  password exchanges for a session, and the session reads the user's own profile back. Swap
  the identity provider for a fake and none of the three steps prove anything.

  The temporary password is only returned by the create call, so the user is deleted first
  to guarantee a fresh create (a reused username answers 409 with no password).

  Background:
    * url baseUrl
    * def username = 'karate-temp-password-user-' + runId

  Scenario: the temporary password logs the user in and reads its own profile
    * def cleared = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(username)' }
    # pass or fail, as admin: the scenario switches to the user's token below
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    * configure afterScenario = function(){ karate.configure('headers', adminHeaders); karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: username }) }
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(username)' }
    * match created.temporaryPassword == '#notnull'

    * def login = call read('classpath:iomete/helpers/user/login.feature') { username: '#(username)', password: '#(created.temporaryPassword)' }

    # act as the user we just logged in as, instead of the suite-wide admin token
    * configure headers = { Authorization: '#("Bearer " + login.accessToken)' }
    Given path 'api/v1/users', username
    When method get
    Then status 200
    And match response.item.username == username
    And match response.item.email == created.user.email

