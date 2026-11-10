@lock=api
Feature: Identity, an admin adds a user to a domain and removes them again

  The membership lives in the real identity store, so this checks the one round trip only it
  can answer: a user added to the domain is listed as a member, and is gone from the list once
  removed. Whether domain access is enforced for non-members depends on the target's
  domainBundleAuth setting (off by default), so it is not asserted here.

  Background:
    * url baseUrl
    * def username = 'karate-domain-member-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    Given path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domainRecord = response.find(d => d.name == domain)
    * match domainRecord == '#notnull'
    * def membersPath = 'api/v1/admin/domains/' + domainRecord.id + '/members'

    # teardown, registered before the user exists so a failed setup still cleans up. It removes
    # the membership if the scenario left it (deleting needs the membership id, not the
    # username) and fails on any unexpected status, then always attempts the user delete.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        try {
          var list = karate.http(baseUrl + '/' + membersPath + '?size=100').headers(adminHeaders).get();
          if (list.status != 200) throw 'listing domain members failed: HTTP ' + list.status;
          var left = list.body.items.filter(function(m) { return m.identity.value == username; });
          for (var i = 0; i < left.length; i++) {
            var res = karate.http(baseUrl + '/' + membersPath + '/' + left[i].id).headers(adminHeaders).delete();
            if (res.status != 204 && res.status != 404) throw 'removing domain member failed: HTTP ' + res.status;
          }
        } finally {
          karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: username });
        }
      }
      """

    * def cleared = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(username)' }
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(username)' }

  Scenario: an added user is listed as a domain member, and removal takes them off the list
    Given path membersPath
    And request [ { type: 'USER', value: '#(username)' } ]
    When method post
    Then status 204

    Given path membersPath
    And param size = 100
    When method get
    Then status 200
    * def added = response.items.filter(m => m.identity.value == username)
    * match added == [ { id: '#string', identity: { type: 'USER', value: '#(username)' } } ]

    Given path membersPath, added[0].id
    When method delete
    Then status 204

    Given path membersPath
    And param size = 100
    When method get
    Then status 200
    * match response.items[*].identity.value !contains username
