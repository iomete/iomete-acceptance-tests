@lock=api
Feature: Resource groups, a role assigned on a group gives access to the resources in it

  One main flow through resource groups: create a group, move a Spark job definition into it, give
  a user a custom resource role on it and a second user a legacy bundle permission, then take the
  role away. The job is only a definition and is never run, so nothing deploys compute or Spark.
  Users are real logins, never the admin token.

  Not tested here: the Reader / Contributor / Owner verb matrix per asset type, the default owner
  (the creator) and owner changes, tag filters beyond one, validation errors and 403 / 404 / 409
  cases. They stay in iom-identity's own tests.

  Background:
    * url baseUrl
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    # older builds have no resource-groups API: skip instead of failing
    * def probed = call read('classpath:iomete/helpers/resourcegroup/probe-resource-groups.feature')
    * if (!probed.available) { karate.log('resource-groups API not present on ' + platformVersion + ': skipping'); karate.abort() }
    # role grants only count with the resourceGroupRoles flag on, which is off by default
    * def rolesCount = karate.callSingle('classpath:iomete/helpers/settings/enable-resource-group-roles.feature').rolesCount
    * if (!rolesCount) { karate.log('resourceGroupRoles flag is off and IOMETE_RESOURCE_GROUP_ROLES_SET_FLAG is not true: skipping'); karate.abort() }
    * def asUser = function(login){ karate.configure('headers', { Authorization: 'Bearer ' + login.accessToken }) }

    Given path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domainRecord = response.find(d => d.name == domain)
    * match domainRecord == '#notnull'
    * def membersPath = 'api/v1/admin/domains/' + domainRecord.id + '/members'

  Scenario: a role grants access on the group's job, a legacy grant works alongside it, and unassigning the role removes only the role's access
    # the group, job and role are per attempt, not just per run: CI retries a failed feature under the same run id
    * def attempt = java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)
    * def rgName = 'karate-rg-access-' + runId + '-' + attempt
    * def jobName = 'karate-rg-access-job-' + runId + '-' + attempt
    * def roleName = 'karate-rr-access-' + runId + '-' + attempt
    * def namespaceRole = 'karate-rg-ns-' + runId + '-' + attempt
    * def roleUser = 'karate-rg-access-role-' + runId
    * def legacyUser = 'karate-rg-access-legacy-' + runId
    # owns the group, so the platform does not file the admin's other new assets in it (it picks the creator's owned groups)
    * def groupOwner = 'karate-rg-access-owner-' + runId
    * def allUsers = ['#(roleUser)', '#(legacyUser)', '#(groupOwner)']
    * def resourceGroupId = null

    # teardown: back to admin first, then undo in dependency order (job, group, role, members, users).
    # Every step runs, and one failure fails the run, so a leaked group or user is never silent.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var errors = [];
        var step = function(label, fn) { try { fn(); } catch (e) { errors.push(label + ': ' + e); } };
        step('job', function() { karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName }); });
        step('group', function() { karate.call('classpath:iomete/helpers/resourcegroup/delete-resource-group.feature', { groupId: resourceGroupId }); });
        step('role', function() { karate.call('classpath:iomete/helpers/resourcegroup/delete-resource-role.feature', { roleName: roleName }); });
        step('namespace role', function() {
          var res = karate.http(baseUrl + '/api/v1/domains/' + domain + '/roles/' + namespaceRole).headers(adminHeaders).delete();
          if (res.status != 200 && res.status != 204 && res.status != 400 && res.status != 404) throw 'HTTP ' + res.status;
        });
        step('domain members', function() {
          var list = karate.http(baseUrl + '/' + membersPath + '?size=100').headers(adminHeaders).get();
          if (list.status != 200) throw 'HTTP ' + list.status;
          allUsers.forEach(function(u) {
            list.body.items.filter(function(m) { return m.identity.value == u; }).forEach(function(m) {
              var res = karate.http(baseUrl + '/' + membersPath + '/' + m.id).headers(adminHeaders).delete();
              if (res.status != 204 && res.status != 404) throw 'HTTP ' + res.status;
            });
          });
        });
        allUsers.forEach(function(u) {
          step('user ' + u, function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: u }); });
        });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    # delete first: a user left by a failed retry comes back with no temporaryPassword, which login needs
    * def clearedRoleUser = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(roleUser)' }
    * def clearedLegacyUser = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(legacyUser)' }
    * def clearedGroupOwner = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(groupOwner)' }
    * def createdRoleUser = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(roleUser)' }
    * def createdLegacyUser = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(legacyUser)' }
    * def createdGroupOwner = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(groupOwner)' }
    Given path membersPath
    And request [ { type: 'USER', value: '#(roleUser)' }, { type: 'USER', value: '#(legacyUser)' } ]
    When method post
    Then status 204

    # updating a job also checks the job's namespace, so the role user gets a domain role that opens
    # every namespace. Platforms without role namespace grants answer 404 and open new namespaces to everyone
    Given path 'api/v1/domains', domain, 'roles'
    And request { name: '#(namespaceRole)', description: 'karate namespace use for the role user', permissions: [] }
    When method post
    Then assert responseStatus == 200 || responseStatus == 201
    Given path 'api/v1/domains', domain, 'members', 'USER', roleUser, 'roles'
    And request ['#(namespaceRole)']
    When method post
    Then status 204
    Given path 'api/v1/domains', domain, 'roles', namespaceRole, 'namespaces'
    And request { all: true, namespaces: [] }
    When method put
    Then assert responseStatus == 200 || responseStatus == 404

    # the job definition first, so it sits in its usual group, the source of the move below
    * def job = call read('classpath:iomete/helpers/job/create-job.feature') { name: '#(jobName)' }
    * def jobId = job.jobId
    Given path 'api/v1/domains/' + domain + '/spark/jobs', jobId
    When method get
    Then status 200
    * def sourceGroupId = response.item.bundle.id

    # create the group owned by the throwaway user (not the admin), with one tag found again through the tag filter
    * def created = call read('classpath:iomete/helpers/resourcegroup/create-resource-group.feature') { name: '#(rgName)', owner: { id: '#(groupOwner)', type: 'USER' }, tags: { env: 'karate' } }
    * def resourceGroupId = created.groupId
    * match created.group.owner == { id: '#(groupOwner)', type: 'USER' }
    * match created.group.tags == { env: 'karate' }
    # the list shows only the caller's own groups by default, and the throwaway user owns this one
    Given path 'api/v1/resource-groups'
    And param domain = domain
    And param scope = 'ALL'
    And param tag = 'env:karate'
    When method get
    Then status 200
    And match response.items[*].groupId contains resourceGroupId

    # move the job into the new group
    Given path 'api/v1/resource-groups', sourceGroupId, 'resources/move'
    And request { destinationGroupId: '#(resourceGroupId)', resources: { SPARK_JOB: ['#(jobId)'] } }
    When method post
    Then status 204

    # a custom resource role (VIEW + EDIT), next to the built-in Reader / Contributor / Owner
    * def rolesPath = 'api/v1/domains/' + domain + '/resource-roles'
    Given path rolesPath
    And request { name: '#(roleName)', description: 'karate api test role', permissions: { SPARK_JOB: ['VIEW', 'EDIT'] } }
    When method post
    Then status 201
    Given path rolesPath
    When method get
    Then status 200
    And match response[*].name contains ['Reader', 'Contributor', 'Owner', '#(roleName)']

    # assign it to the first user, read the assignment back
    * def assignmentsPath = 'api/v1/resource-groups/' + resourceGroupId + '/assignments'
    Given path assignmentsPath
    And request { usernames: ['#(roleUser)'], roleNames: ['#(roleName)'] }
    When method post
    Then status 201
    Given path assignmentsPath
    When method get
    Then status 200
    And match karate.toString(response) contains roleName

    # the second user gets a legacy bundle permission (VIEW) on the same group
    * def grant = { SPARK_JOB: { users: {}, groups: {} } }
    * eval grant.SPARK_JOB.users[legacyUser] = ['VIEW']
    Given path 'api/v1/bundles', resourceGroupId, 'permissions'
    And request grant
    When method post
    Then assert responseStatus == 200 || responseStatus == 204

    # the V2 job endpoints check the permission on the asset itself; the V1 ones only check a
    # domain-level permission, which is not enforced here (see AGENTS.md, Identity / auth semantics)
    * def jobPath = 'api/v2/domains/' + domain + '/spark/jobs'

    # the role user can view and update the job, but not delete it (delete is `MANAGE`)
    * def roleLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(roleUser)', password: '#(createdRoleUser.temporaryPassword)' }
    * asUser(roleLogin)
    # a resourceGroupRoles flag just turned on takes up to about 90s to reach every service,
    # and the all-in-one environment is slower due to single-node constraints, so allow 3 minutes
    * configure retry = { count: 90, interval: 2000 }
    Given path jobPath, jobId
    And retry until responseStatus != 403
    When method get
    Then status 200
    And match response.id == jobId
    # the namespace grant reaches iom-cluster through a cache of about 30s,
    # allow extra time for the all-in-one environment
    * configure retry = { count: 45, interval: 2000 }
    Given path jobPath, jobId
    And request job.updateRequest
    And retry until responseStatus != 403
    When method put
    Then status 200
    Given path jobPath, jobId
    When method delete
    Then assert responseStatus == 403 || responseStatus == 404

    # the legacy user can view it
    * def legacyLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(legacyUser)', password: '#(createdLegacyUser.temporaryPassword)' }
    * asUser(legacyLogin)
    Given path jobPath, jobId
    When method get
    Then status 200

    # unassign the role: the role user loses access, the legacy user keeps it
    * karate.configure('headers', adminHeaders)
    Given path assignmentsPath, 'users', roleUser, roleName
    When method delete
    Then status 204
    * asUser(roleLogin)
    Given path jobPath, jobId
    When method get
    Then assert responseStatus == 403 || responseStatus == 404
    * asUser(legacyLogin)
    Given path jobPath, jobId
    When method get
    Then status 200
