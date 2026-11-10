@lock=api
Feature: Identity, a bundle's owner grants and revokes a member's access, and a non-owner cannot

  Bundle access is decided by the real identity store: the owner of a bundle can manage who
  holds permissions on it, and a user who is neither owner nor admin cannot. One round trip
  over real logins covers it — grant is readable from the member list, revoke takes it away,
  and an outsider is refused. Swap the identity store for a fake and none of it holds.

  Permission validation, ownership transfer, asset moves and archive rules are the identity
  service's own logic, so they stay in its tests rather than here.

  Background:
    * url baseUrl
    * def ownerName = 'karate-bundle-owner-' + runId
    * def memberName = 'karate-bundle-member-' + runId
    * def bundleName = 'karate-bundle-' + runId

    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # teardown, registered before any user exists so a failed setup step still cleans up. It
    # archives the bundle (failing on an unexpected status) and always attempts both user deletes.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        try {
          var id = karate.get('bundleId');
          if (id) {
            var res = karate.http(baseUrl + '/api/v1/bundles/' + id).headers(adminHeaders).delete();
            if (res.status != 204 && res.status != 404) throw 'archiving the bundle failed: HTTP ' + res.status;
          }
        } finally {
          try {
            karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: ownerName });
          } finally {
            karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: memberName });
          }
        }
      }
      """

    * def clearedOwner = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(ownerName)' }
    * def clearedMember = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(memberName)' }
    * def createdOwner = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(ownerName)' }
    * def createdMember = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(memberName)' }
    * def ownerLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(ownerName)', password: '#(createdOwner.temporaryPassword)' }
    * def memberLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(memberName)', password: '#(createdMember.temporaryPassword)' }
    * def ownerHeaders = { Authorization: '#("Bearer " + ownerLogin.accessToken)' }
    * def memberHeaders = { Authorization: '#("Bearer " + memberLogin.accessToken)' }

  Scenario: the owner grants and revokes a member's permission, and a non-owner is refused
    # admin creates the bundle on behalf of the owner user
    * configure headers = adminHeaders
    Given path 'api/v1/bundles'
    And request { name: '#(bundleName)', description: 'karate bundle access', domain: '#(domain)', bundleType: 'RESOURCE', owner: { id: '#(ownerName)', type: 'USER' } }
    When method post
    Then status 200
    * def bundleId = response.bundleId
    * match bundleId == '#string'

    # the owner finds it in their own list. Leaving scope out is the point: it is optional, and every
    # other call to this endpoint names it, so nothing else exercises the server's default. Before
    # 4.0.2 that answers 500, so older targets name it too.
    * configure headers = ownerHeaders
    * def scopeHasDefault = platformAtLeast('4.0.2')
    Given path 'api/v1/bundles'
    And params scopeHasDefault ? { domain: domain } : { domain: domain, scope: 'OWNED' }
    When method get
    Then status 200
    And match response.items[*].bundleId contains bundleId
    And match each response.items[*].owner.id == ownerName

    * def grant = { COMPUTE: { users: {}, groups: {} } }
    * eval grant.COMPUTE.users[memberName] = ['VIEW']

    # a user who neither owns the bundle nor is an admin cannot hand out permissions on it
    * configure headers = memberHeaders
    Given path 'api/v1/bundles', bundleId, 'permissions'
    And request grant
    When method post
    Then status 403

    # the owner can, and the grant shows up in the bundle's member list
    * configure headers = ownerHeaders
    Given path 'api/v1/bundles', bundleId, 'permissions'
    And request grant
    When method post
    Then status 204

    Given path 'api/v1/bundles', bundleId, 'members'
    When method get
    Then status 200
    And match response.items[*].actorId contains memberName

    # and the member's own record holds exactly the permission that was granted
    Given path 'api/v1/bundles', bundleId, 'actor', memberName, 'actorType', 'USER'
    When method get
    Then status 200
    And match response.actorName == memberName
    And match response.permissions == [ { assetType: '#string', actions: ['VIEW'] } ]

    # revoking takes the member off the list again
    Given path 'api/v1/bundles', bundleId, 'permissions'
    And request { actorType: 'USER', actorId: '#(memberName)' }
    When method delete
    Then status 204

    Given path 'api/v1/bundles', bundleId, 'members'
    When method get
    Then status 200
    And match response.items[*].actorId !contains memberName

    Given path 'api/v1/bundles', bundleId, 'actor', memberName, 'actorType', 'USER'
    When method get
    Then status 200
    And match response.permissions == []
