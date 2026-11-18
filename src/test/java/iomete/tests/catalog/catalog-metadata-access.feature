@lock=sql
Feature: Data catalog metadata, the full table listing answers members of the domain only

  The console pages through every table a domain may see with `data-catalog/metadata`, on the
  current route and the deprecated v1 one. Both answer a member of the domain, limited to the
  catalogs the domain may use, and refuse a user who is not in it. The members are real logins,
  not the admin token, which reaches every admin-managed domain.

  Background:
    * url baseUrl
    # members-only metadata arrived in 4.0.3; builds from main count as newer
    * if (!platformAtLeast('4.0.3')) karate.log('platform ' + platformVersion + ' predates members-only catalog metadata, skipping')
    * if (!platformAtLeast('4.0.3')) karate.abort()
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    # 501 means the catalog is not wired up here and 204 means it is. Anything else is a real
    # failure and must not pass as a skip.
    Given path 'api/v2/domains/' + domain + '/data-catalog/enabled'
    When method get
    * if (responseStatus == 501) karate.log('data catalog is not enabled on this environment, skipping')
    * if (responseStatus == 501) karate.abort()
    Then status 204

  Scenario: a domain member pages through the catalog metadata on both routes, an outsider is refused
    The run's indexed table has to turn up for the member, so the listing is not passing on an
    empty answer. It is paged with no stable order, and other runs add tables to the same catalog
    while it walks, so a row can move to a page already read. The scenario walks the pages until it
    finds the table, and walks again from the first page, up to 5 times, before it fails.

    * def indexed = karate.callSingle('classpath:iomete/tests/catalog/setup/indexed-table.feature', { domain: domain })
    * def memberUser = 'karate-meta-member-' + runId
    * def outsiderUser = 'karate-meta-outsider-' + runId

    Given path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domainRecord = response.find(d => d.name == domain)
    * match domainRecord == '#notnull'
    * def membersPath = 'api/v1/admin/domains/' + domainRecord.id + '/members'

    # teardown: the member's domain grant (deleting a user leaves it behind), then the membership
    # (deleting it needs the membership id), then both users. Every step runs, and one failure
    # fails the run.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var errors = [];
        var step = function(label, fn) { try { fn(); } catch (e) { errors.push(label + ': ' + e); } };
        step('grant', function() { karate.call('classpath:iomete/helpers/user/revoke-bundle-grants.feature', { username: memberUser, domainRoot: true }); });
        step('membership', function() {
          var list = karate.http(baseUrl + '/' + membersPath + '?size=100').headers(adminHeaders).get();
          if (list.status != 200) throw 'listing domain members failed: HTTP ' + list.status;
          list.body.items.filter(function(m) { return m.identity.value == memberUser; }).forEach(function(m) {
            var res = karate.http(baseUrl + '/' + membersPath + '/' + m.id).headers(adminHeaders).delete();
            if (res.status != 204 && res.status != 404) throw 'HTTP ' + res.status;
          });
        });
        [memberUser, outsiderUser].forEach(function(u) {
          step('user ' + u, function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: u }); });
        });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    # only a new user comes with a password, so leftovers of an earlier attempt go first
    * def clearedMember = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(memberUser)' }
    * def clearedOutsider = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(outsiderUser)' }
    * def createdMember = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(memberUser)' }
    * def createdOutsider = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(outsiderUser)' }
    # membership, plus the permission the listing checks where domain bundles are on
    * def granted = call read('classpath:iomete/helpers/domain/grant-domain-permissions.feature') { username: '#(memberUser)', permissions: ['VIEW_DATA_CATALOG'] }

    * def memberLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(memberUser)', password: '#(createdMember.temporaryPassword)' }
    * def outsiderLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(outsiderUser)', password: '#(createdOutsider.temporaryPassword)' }
    * def memberHeaders = { Authorization: '#("Bearer " + memberLogin.accessToken)' }
    * def outsiderHeaders = { Authorization: '#("Bearer " + outsiderLogin.accessToken)' }

    # pages through a route as the member until the indexed table turns up
    * def pageSize = 500
    * def walkOnce =
      """
      function(route) {
        for (var page = 0; page < 40; page++) {
          var res = karate.http(baseUrl + '/' + route + '?page=' + page + '&size=' + pageSize).headers(memberHeaders).get();
          if (res.status != 200) return { status: res.status, found: false, page: page };
          var rows = res.body;
          if (rows.find(function(t) { return t.catalog == indexed.catalogName && t.schema == indexed.database && t.name == indexed.tableName; })) return { status: 200, found: true, page: page };
          if (rows.length < pageSize) return { status: 200, found: false, page: page };
        }
        return { status: 200, found: false, page: 40 };
      }
      """
    # the pages have no stable order and overlapping runs add tables mid-walk, so a miss walks again
    * def findIndexed =
      """
      function(route) {
        var result = null;
        for (var attempt = 1; attempt <= 5; attempt++) {
          result = walkOnce(route);
          if (result.found || result.status != 200) return result;
          karate.log('indexed table not found on', route, 'in walk', attempt, 'of 5, walking again');
          java.lang.Thread.sleep(2000);
        }
        return result;
      }
      """

    # a new member's domains are cached for a few seconds, so the first read waits that out
    * configure headers = memberHeaders
    * configure retry = { count: 15, interval: 2000 }
    Given path 'api/v2/domains', domain, 'data-catalog/metadata'
    And params { page: 0, size: 1 }
    And retry until responseStatus != 403
    When method get
    Then status 200
    And match response == '#[] #object'
    And match each response contains { catalog: '#string', schema: '#string', name: '#string' }

    * def v2 = findIndexed('api/v2/domains/' + domain + '/data-catalog/metadata')
    * match v2 contains { status: 200, found: true }
    * def v1 = findIndexed('api/v1/domains/' + domain + '/data-catalog/metadata')
    * match v1 contains { status: 200, found: true }

    # karate.http leaves its URL on the scenario's request, so the walks above need it reset
    * url baseUrl
    * configure headers = outsiderHeaders
    Given path 'api/v2/domains', domain, 'data-catalog/metadata'
    When method get
    Then status 403
    Given path 'api/v1/domains', domain, 'data-catalog/metadata'
    When method get
    Then status 403
