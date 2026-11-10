@lock=api
Feature: Identity, an admin role granted to a group reaches its members, and removal takes it away

  GET api/v1/admin/domains/{id}/members is guarded by AdminRole.ANY. A member of a group that
  holds an admin role can call it, and the role shows up on the member's own account as
  inherited from the group; removing the role from the group takes it off the member again.
  A check a faked identity provider could not make.

  The identity service caches a user's admin roles, so a denial (before the grant, or after
  the removal) is not asserted: the stale answer would be served. The probe is called once,
  after the grant, and the removal is read from the member's role list.

  Background:
    * url baseUrl
    * def username = 'karate-revoke-user-' + runId
    * def groupName = 'karate-revoke-group-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # teardown, registered before the user and group exist so a failed setup step still cleans
    # up; the user delete is attempted even if the group delete fails (both helpers tolerate a
    # fixture that is already gone)
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        try {
          karate.call('classpath:iomete/helpers/group/delete-group.feature', { name: groupName });
        } finally {
          karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: username });
        }
      }
      """

    * def clearedGroup = call read('classpath:iomete/helpers/group/delete-group.feature') { name: '#(groupName)' }
    * def clearedUser = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(username)' }
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(username)' }
    * def group = call read('classpath:iomete/helpers/group/create-group.feature') { name: '#(groupName)' }
    * def groupUsersPath = 'api/v1/admin/identity/groups/' + groupName + '/users'
    * def groupRolesPath = 'api/v1/admin/identity/groups/' + groupName + '/roles'
    * def userRolesPath = 'api/v1/admin/identity/users/' + username + '/roles'

    Given path groupUsersPath
    And request [ '#(username)' ]
    When method post
    Then status 204

    Given path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domainRecord = response.find(d => d.name == domain)
    * match domainRecord == '#notnull'
    * def probePath = 'api/v1/admin/domains/' + domainRecord.id + '/members'

  Scenario: a role granted to the group reaches the member, and removing it takes it away
    Given path groupRolesPath
    And request [ 'DOMAIN_MANAGER' ]
    When method post
    Then status 200

    # the member's own account lists the role, inherited from the group
    Given path userRolesPath
    When method get
    Then status 200
    And match response contains { name: 'DOMAIN_MANAGER', groups: ['#(groupName)'] }

    # and the member can use it: log in now and call the admin-guarded endpoint
    * def login = call read('classpath:iomete/helpers/user/login.feature') { username: '#(username)', password: '#(created.temporaryPassword)' }
    * configure headers = { Authorization: '#("Bearer " + login.accessToken)' }
    Given path probePath
    When method get
    Then status 200

    # removing the role from the group takes it off the member
    * configure headers = adminHeaders
    Given path groupRolesPath
    And request [ 'DOMAIN_MANAGER' ]
    When method delete
    Then assert responseStatus == 200 || responseStatus == 204

    Given path userRolesPath
    When method get
    Then status 200
    And match response[*].name !contains 'DOMAIN_MANAGER'
