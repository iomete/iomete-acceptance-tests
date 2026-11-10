@lock=api
Feature: Identity, users and groups from LDAP are synced in and removed again

  A sync reads the real directory: the users and groups already in it show up in IOMETE as
  LDAP users and groups, with their members. When the filter stops matching them, the next sync
  removes them. A user created in IOMETE itself is left alone. The test never writes to the
  directory.
  The LDAP integration is one setting for the whole environment, and a sync replaces every LDAP
  user and group in it, so only run this against a test environment.
  Skips unless IOMETE_LDAP_URL and IOMETE_LDAP_BIND_PASSWORD are set (see AGENTS.md).

  Background:
    * url baseUrl
    * def env = function(name, fallback){ return java.lang.System.getenv(name) || fallback }
    * def ldapUrl = env('IOMETE_LDAP_URL', null)
    * def bindCredential = env('IOMETE_LDAP_BIND_PASSWORD', null)
    * if (!ldapUrl || !bindCredential) karate.log('no test LDAP directory configured (IOMETE_LDAP_URL, IOMETE_LDAP_BIND_PASSWORD), skipping')
    * if (!ldapUrl || !bindCredential) karate.abort()

    * def baseDn = env('IOMETE_LDAP_BASE_DN', 'dc=iomete,dc=com')
    * def bindDn = env('IOMETE_LDAP_BIND_DN', 'cn=admin,' + baseDn)
    * def usersDn = env('IOMETE_LDAP_USERS_DN', 'ou=users,' + baseDn)
    * def groupsDn = env('IOMETE_LDAP_GROUPS_DN', 'ou=groups,' + baseDn)
    * def localUser = 'karate-ldap-local-' + runId
    * def listLdap = function(){ return karate.call('classpath:iomete/tests/identity/setup/ldap-identities.feature') }
    * def integrationPath = 'api/v1/admin/identity/ldap-integration'
    * def integrationBody =
      """
      function(userFilter, groupFilter) {
        return {
          settings: {
            connection: { url: ldapUrl, bindDn: bindDn, bindCredential: bindCredential },
            userSearchFilter: {
              usersDn: usersDn,
              userObjectClasses: 'inetOrgPerson',
              filter: userFilter,
              attributeMapping: { username: 'uid', email: 'mail', firstName: 'givenName', lastName: 'sn' }
            },
            groupSearchFilter: {
              enabled: true,
              groupsDn: groupsDn,
              groupObjectClasses: 'groupOfNames',
              filter: groupFilter,
              attributeMapping: { name: 'cn', membership: 'member', membershipAttributeType: 'DN' }
            },
            syncSettings: { periodicFullSyncEnabled: false, fullSyncPeriodInSeconds: 86400 }
          }
        };
      }
      """

    # teardown: deleting the integration also removes everything it imported
    * configure afterScenario =
      """
      function() {
        try { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: localUser }); } catch (e) { karate.log('user teardown failed:', e); }
        karate.call('classpath:iomete/tests/identity/setup/ldap-delete-integration.feature');
      }
      """

  Scenario: LDAP users and groups are synced in with their members, and removed once the filter drops them
    # a leftover integration would otherwise refuse the create
    * def cleared = call read('classpath:iomete/tests/identity/setup/ldap-delete-integration.feature')
    * def local = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(localUser)' }

    Given path integrationPath
    And request integrationBody('(objectClass=inetOrgPerson)', '(objectClass=groupOfNames)')
    When method post
    Then status 201

    # create does not apply an enabled flag, so enable it explicitly
    Given path integrationPath, 'enable'
    And request {}
    When method put
    Then status 204

    # a sync returns once it has finished, so the result is visible straight away
    Given path integrationPath, 'sync-all'
    And request {}
    When method post
    Then status 204
    * def listed = listLdap()
    * match listed.users == '#[_ > 0]'
    * match listed.groups == '#[_ > 0]'

    Given path 'api/v1/groups', listed.groups[0], 'users'
    When method get
    Then status 200
    And match response == '#[_ > 0]'

    # the user created in IOMETE itself is still there
    Given path 'api/v1/users'
    And params { origin: 'IOMETE', searchText: '#(localUser)', size: 10 }
    When method get
    Then status 200
    And match response.items[*].username contains localUser

    # a filter that matches nothing leaves no LDAP users or groups after the next sync
    * def nothing = '(uid=karate-no-such-entry-' + runId + ')'
    Given path integrationPath
    And request integrationBody(nothing, '(cn=karate-no-such-entry-' + runId + ')')
    When method put
    Then status 200

    Given path integrationPath, 'sync-all'
    And request {}
    When method post
    Then status 204
    * def after = listLdap()
    * match after.users == []
    * match after.groups == []

    Given path 'api/v1/users'
    And params { origin: 'IOMETE', searchText: '#(localUser)', size: 10 }
    When method get
    Then status 200
    And match response.items[*].username contains localUser
