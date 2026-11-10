@ignore
Feature: Create (or reuse) a data-plane user so other tests have a principal to act on.
  Generic helper — callers pass at least a username; email/firstName/lastName are optional
  and default deterministically from the username so re-runs reuse the same user:
    karate.call('classpath:iomete/helpers/user/create-user.feature',
                { username: 'karate-test-user' })
    karate.call('classpath:iomete/helpers/user/create-user.feature',
                { username: 'analyst', email: 'analyst@iomete.test', firstName: 'Ana', lastName: 'Lyst' })
  Pass type: 'SERVICE_ACCOUNT' for a service account; omitted, the platform creates a person.
  Returns:
    username          the created/existing username (lowercased, as the API stores it)
    user              the full user record from GET .../users/{username}
    temporaryPassword the generated one-time password on first create, or null if it already existed

  Scenario: create the user if missing (409 = already there), then load its record
    * def username = username.toLowerCase()
    * def email = karate.get('email', username + '@iomete.test')
    * def firstName = karate.get('firstName', username)
    * def lastName = karate.get('lastName', 'test-user')
    * def type = karate.get('type', null)
    * def usersPath = 'api/v1/admin/identity/users'

    * def createRequest =
      """
      {
        username: '#(username)',
        email: '#(email)',
        firstName: '#(firstName)',
        lastName: '#(lastName)',
        type: '##(type)'
      }
      """

    # create if missing — 409 means the username (or email) already exists, which is fine
    Given url baseUrl
    And path usersPath
    And request createRequest
    When method post
    Then assert responseStatus == 201 || responseStatus == 409
    * def temporaryPassword = responseStatus == 201 ? response.temporaryPassword : null

    # load the record so callers get a consistent shape whether we created or reused it
    Given url baseUrl
    And path usersPath, username
    When method get
    Then status 200
    * def user = response.item
    * match user == '#notnull'
