@lock=api
Feature: Namespace access, a domain role opens a namespace to its members

  One main flow through namespace access: a namespace assigned to a fresh domain is closed to a
  plain member. An admin creates a domain role, gives it to one user and lists the namespace on it,
  and only that user can use the namespace. Users are real logins, and "can use" is what the user's
  own namespace list shows.

  The flow runs in a domain of its own, so the role and its grant never reach the suite's domain or
  the other runs. Domains can only be deleted from 4.0.2, so older builds skip.

  Not tested here: `all: true`, group roles, the implicit default role, bundle `USE` grants and the
  403 for a member without `iam_settings: manage`. They stay in iom-identity's and iom-cluster's tests.

  Background:
    * url baseUrl
    * if (!platformAtLeast('4.0.2')) { karate.log('deleting the test domain needs 4.0.2+: skipping on ' + platformVersion); karate.abort() }
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    * def probed = call read('classpath:iomete/helpers/resourcegroup/probe-resource-groups.feature')
    * if (!probed.available) { karate.log('resource-groups API not present on ' + platformVersion + ': skipping'); karate.abort() }
    # role grants only count with the resourceGroupRoles flag on, which is off by default
    * def rolesCount = karate.callSingle('classpath:iomete/helpers/settings/enable-resource-group-roles.feature').rolesCount
    * if (!rolesCount) { karate.log('resourceGroupRoles flag is off and IOMETE_RESOURCE_GROUP_ROLES_SET_FLAG is not true: skipping'); karate.abort() }
    # per attempt, not just per run: a deleted domain keeps its id reserved, so a retry needs a new one
    * def nsDomain = 'karate-nsa-' + runId + '-' + java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)
    * def memberUser = 'karate-nsa-member-' + runId
    * def otherUser = 'karate-nsa-other-' + runId
    * def allUsers = ['#(memberUser)', '#(otherUser)']
    * def roleName = 'karate-nsa-role-' + runId

  Scenario: a new namespace is closed to plain members until a domain role lists it
    * def namespace = null
    * def dataPlane = null

    # teardown: back to admin first, then undo in dependency order (role, assignment, domain, users).
    # Every step runs, and one failure fails the run, so a leaked domain or user is never silent.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var errors = [];
        var step = function(label, fn) { try { fn(); } catch (e) { errors.push(label + ': ' + e); } };
        step('role', function() {
          var res = karate.http(baseUrl + '/api/v1/domains/' + nsDomain + '/roles/' + roleName).headers(adminHeaders).delete();
          if (res.status != 200 && res.status != 204 && res.status != 400 && res.status != 404) throw 'HTTP ' + res.status;
        });
        step('namespace assignment', function() {
          if (!namespace) return;
          var res = karate.http(baseUrl + '/api/v2/domains/' + nsDomain + '/namespaces/' + namespace + '?dataPlane=' + dataPlane).headers(adminHeaders).delete();
          if (res.status != 200 && res.status != 404) throw 'HTTP ' + res.status;
        });
        step('domain', function() {
          var res = karate.http(baseUrl + '/api/v1/admin/domains/' + nsDomain).headers(adminHeaders).delete();
          if (res.status != 204 && res.status != 400 && res.status != 404) throw 'HTTP ' + res.status;
        });
        allUsers.forEach(function(u) {
          step('user ' + u, function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: u }); });
        });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    # the namespace the suite's own domain runs in, so no namespace name or data plane is hardcoded
    Given path 'api/v3/domains/' + domain + '/namespaces'
    When method get
    Then status 200
    * def source = response.find(n => n.namespace != 'iomete-system')
    * match source == '#notnull'
    * def namespace = source.namespace
    * def dataPlane = source.dataPlane

    * karate.call('classpath:iomete/helpers/domain/create-domain.feature', { domainId: nsDomain })
    * def clearedMember = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(memberUser)' }
    * def clearedOther = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(otherUser)' }
    * def createdMember = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(memberUser)' }
    * def createdOther = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(otherUser)' }
    # one call for everyone: it sets the member list, and the admin has to stay on it to list the domain's namespaces
    Given path 'api/v1/user'
    When method get
    Then status 200
    * def me = response.username
    Given path 'api/v1/admin/domains', nsDomain, 'members'
    And request [ { type: 'USER', value: '#(me)' }, { type: 'USER', value: '#(memberUser)' }, { type: 'USER', value: '#(otherUser)' } ]
    When method post
    Then status 204

    * karate.call('classpath:iomete/helpers/namespace/assign-namespace.feature', { domain: nsDomain, namespace: namespace, dataPlane: dataPlane })

    * def memberLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(memberUser)', password: '#(createdMember.temporaryPassword)' }
    * def otherLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(otherUser)', password: '#(createdOther.temporaryPassword)' }
    * def asLogin = function(login) { return { Authorization: 'Bearer ' + login.accessToken } }
    * def namespacesOf = function(login) { var res = karate.http(baseUrl + '/api/v3/domains/' + nsDomain + '/namespaces').headers(asLogin(login)).get(); if (res.status != 200) karate.fail('namespace list answered HTTP ' + res.status); return res.body.map(function(n) { return n.namespace }) }

    # a new namespace has no default member, so a plain member cannot use it
    * match namespacesOf(memberLogin) !contains namespace
    * match namespacesOf(otherLogin) !contains namespace

    # a domain role that lists the namespace, given to one user. The admin's domain list was read
    # before this domain existed, so domain-checked calls answer 403 for a few seconds
    * url baseUrl
    * configure retry = { count: 15, interval: 2000 }
    Given path 'api/v1/domains', nsDomain, 'roles'
    And request { name: '#(roleName)', description: 'karate namespace access role', permissions: [] }
    And retry until responseStatus != 403
    When method post
    Then assert responseStatus == 200 || responseStatus == 201
    Given path 'api/v1/domains', nsDomain, 'members', 'USER', memberUser, 'roles'
    And request ['#(roleName)']
    And retry until responseStatus != 403
    When method post
    Then status 204
    Given path 'api/v1/domains', nsDomain, 'roles', roleName, 'namespaces'
    And request { all: false, namespaces: [ { namespace: '#(namespace)', dataPlane: '#(dataPlane)' } ] }
    And retry until responseStatus != 403
    When method put
    Then status 200
    Given path 'api/v1/domains', nsDomain, 'roles', roleName, 'namespaces'
    When method get
    Then status 200
    And match response.namespaces contains { namespace: '#(namespace)', dataPlane: '#(dataPlane)' }
    * def grantedAt = java.lang.System.currentTimeMillis()

    # only that user can use the namespace now. Role grants reach iom-cluster through a cache of
    # about 30s, and a resourceGroupRoles flag just turned on takes up to about 90s. The all-in-one
    # environment is slower due to single-node constraints, so allow 3 minutes
    * def waitUntil = function(fn) { for (var i = 0; i < 90; i++) { if (fn()) return true; java.lang.Thread.sleep(2000) } return false }
    * assert waitUntil(function() { return namespacesOf(memberLogin).indexOf(namespace) >= 0 })
    # the other user's empty list was cached before the grant, so read it only once that entry has expired
    * eval var wait = grantedAt + 35000 - java.lang.System.currentTimeMillis(); if (wait > 0) java.lang.Thread.sleep(wait)
    * match namespacesOf(otherLogin) !contains namespace
