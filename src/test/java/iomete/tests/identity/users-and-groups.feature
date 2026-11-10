@lock=api
Feature: Identity, users and groups as an admin manages them

  The user and group records live in the real identity store, so these scenarios check the
  things only that store can answer: that a new account is findable by search, that a
  membership written on the group is readable from the user's own view, and that an admin
  role assigned to a group is reflected back. Swap the store for a fake and none of it holds.

  Duplicate-name rejection, description edits and user-type changes are the identity
  service's own rules, so they stay in its tests rather than here.

  Background:
    * url baseUrl
    * def alice = 'karate-groups-alice-' + runId
    * def bob = 'karate-groups-bob-' + runId
    * def groupName = 'karate-groups-team-' + runId

    # delete first so each run starts from a known state
    * def clearedGroup = call read('classpath:iomete/helpers/group/delete-group.feature') { name: '#(groupName)' }
    * def clearedAlice = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(alice)' }
    * def clearedBob = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(bob)' }

    # pass or fail; each helper is a no-op when its object is already gone
    * configure afterScenario =
      """
      function() {
        var steps = [
          () => karate.call('classpath:iomete/helpers/group/delete-group.feature', { name: groupName }),
          () => karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: alice }),
          () => karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: bob })
        ];
        // run every step, then fail once, so a leftover never hides behind a log line
        var failures = [];
        steps.forEach(step => { try { step() } catch (e) { karate.log('teardown step failed:', e); failures.push('' + e) } });
        if (failures.length > 0) throw 'teardown failed: ' + failures.join('; ');
      }
      """

  Scenario: a new user is findable in the user list with the profile it was created with
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(alice)', firstName: 'Alice', lastName: 'Docs' }

    Given path 'api/v1/users'
    And param searchText = alice
    And param page = 0
    And param size = 10
    When method get
    Then status 200
    And match response.items contains deep { username: '#(alice)', email: '#(created.user.email)', firstName: 'Alice', lastName: 'Docs' }

  Scenario: group membership is visible from the group and from each user, and removal takes it off
    * def createdAlice = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(alice)' }
    * def createdBob = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(bob)' }
    * def group = call read('classpath:iomete/helpers/group/create-group.feature') { name: '#(groupName)' }
    * def usersPath = 'api/v1/admin/identity/groups/' + groupName + '/users'

    Given path usersPath
    And request [ '#(alice)', '#(bob)' ]
    When method post
    Then status 204

    # the group's own view lists both members
    Given path usersPath
    When method get
    Then status 200
    And match response[*].username contains alice
    And match response[*].username contains bob

    # and each member sees the group from their own account
    Given path 'api/v1/users', alice, 'groups'
    When method get
    Then status 200
    And match response[*].name contains groupName

    Given path 'api/v1/users', bob, 'groups'
    When method get
    Then status 200
    And match response[*].name contains groupName

    # removing one member takes them off the group, leaving the other in place
    Given path usersPath
    And request [ '#(bob)' ]
    When method delete
    Then status 204

    Given path usersPath
    When method get
    Then status 200
    And match response[*].username contains alice
    And match response[*].username !contains bob

    # and it is gone from the removed member's own view too, not just the group's
    Given path 'api/v1/users', bob, 'groups'
    When method get
    Then status 200
    And match response[*].name !contains groupName

  Scenario: an admin role assigned to a group is listed on that group
    * def group = call read('classpath:iomete/helpers/group/create-group.feature') { name: '#(groupName)' }
    * def rolesPath = 'api/v1/admin/identity/groups/' + groupName + '/roles'

    Given path rolesPath
    And request [ 'DOMAIN_MANAGER' ]
    When method post
    Then status 200

    Given path rolesPath
    When method get
    Then status 200
    And match response[*].name contains 'DOMAIN_MANAGER'
