@ignore
Feature: List the LDAP users and groups on the target. Admin action.
    karate.call('classpath:iomete/tests/identity/setup/ldap-identities.feature')
  Returns:
    users   usernames of LDAP users
    groups  names of LDAP groups

  Scenario: list both
    Given url baseUrl
    And path 'api/v1/users'
    And params { origin: 'LDAP', size: 100 }
    When method get
    Then status 200
    * def users = response.items.map(u => u.username)

    Given url baseUrl
    And path 'api/v1/groups'
    And params { size: 100 }
    When method get
    Then status 200
    * def groups = response.items.filter(g => g.origin == 'LDAP').map(g => g.name)
