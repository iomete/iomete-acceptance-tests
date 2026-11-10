@lock=api
Feature: Service accounts, who owns them and who may run as them

  Three real logins — owner, IAM manager, outsider — against the same service-account access
  endpoints, over real auth: each gets the access (200/204) or refusal (403) the real, deployed
  system actually enforces, not an injected SecurityContext.

  Ships in 4.0.2; skips on anything older.

  Background:
    * url baseUrl
    * if (!platformAtLeast('4.0.2')) { karate.log('service-account ownership ships in 4.0.2+: skipping on ' + platformVersion); karate.abort() }
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

  Scenario: an owner and an IAM manager may read and write a service account's access; an unrelated user is refused both
    * def sa = 'karate-sa-authz-' + runId
    * def ownerUser = 'karate-sa-authz-owner-' + runId
    * def iamManager = 'karate-sa-authz-iam-manager-' + runId
    * def outsider = 'karate-sa-authz-outsider-' + runId
    * def writeTargetUser = 'karate-sa-authz-write-user-' + runId
    * def writeTargetGroup = 'karate-sa-authz-write-group-' + runId

    # teardown: restore admin headers first — the failure that triggers this may have left the
    # scenario acting as outsider/owner/IAM manager, none of whom can delete a user
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        try { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: sa }); } catch (e) { karate.log('sa teardown failed:', e); }
        try { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: ownerUser }); } catch (e) { karate.log('owner teardown failed:', e); }
        try { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: iamManager }); } catch (e) { karate.log('iam manager teardown failed:', e); }
        try { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: outsider }); } catch (e) { karate.log('outsider teardown failed:', e); }
      }
      """

    # delete first: a reused user from a failed retry comes back with no temporaryPassword,
    # which login.feature below needs
    * def clearedOwner = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(ownerUser)' }
    * def clearedIamManager = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(iamManager)' }
    * def clearedOutsider = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(outsider)' }

    * def createdSa = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(sa)', type: 'SERVICE_ACCOUNT' }
    * def createdOwner = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(ownerUser)' }
    * def createdIamManager = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(iamManager)' }
    * def createdOutsider = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(outsider)' }
    * def grantedIamManager = call read('classpath:iomete/helpers/user/add-roles.feature') { username: '#(iamManager)', roles: ['IAM_MANAGER'] }

    # admin grants the standing the rest of this scenario exercises
    Given path 'api/v1/service-accounts', sa, 'owners/users'
    And request [ '#(ownerUser)' ]
    When method post
    Then status 204

    * def outsiderLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(outsider)', password: '#(createdOutsider.temporaryPassword)' }
    * configure headers = { Authorization: '#("Bearer " + outsiderLogin.accessToken)' }

    Given path 'api/v1/service-accounts', sa, 'access'
    When method get
    Then status 403

    Given path 'api/v1/service-accounts', sa, 'owners/users'
    And request [ '#(writeTargetUser)' ]
    When method post
    Then status 403

    * def ownerLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(ownerUser)', password: '#(createdOwner.temporaryPassword)' }
    * configure headers = { Authorization: '#("Bearer " + ownerLogin.accessToken)' }

    Given path 'api/v1/service-accounts', sa, 'access'
    When method get
    Then status 200

    Given path 'api/v1/service-accounts', sa, 'run-as/users'
    And request [ '#(writeTargetUser)' ]
    When method post
    Then status 204

    * def iamManagerLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(iamManager)', password: '#(createdIamManager.temporaryPassword)' }
    * configure headers = { Authorization: '#("Bearer " + iamManagerLogin.accessToken)' }

    Given path 'api/v1/service-accounts', sa, 'access'
    When method get
    Then status 200

    Given path 'api/v1/service-accounts', sa, 'owners/groups'
    And request [ '#(writeTargetGroup)' ]
    When method post
    Then status 204
