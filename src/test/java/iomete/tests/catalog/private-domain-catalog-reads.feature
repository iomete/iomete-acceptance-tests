@lock=api
Feature: Private domain catalog reads, a member reads the domain's catalogs and browses its storage

  In a private domain the domain's catalogs and its storage browser answer its members, and a
  platform admin is refused unless they own the domain themselves. One journey on a fresh
  private domain, with a catalog its owner created and a plain member who reads it.

  Private domains arrived in 4.0.3 and can only be created with the `privateDomains` rollout
  flag on, so the scenario skips on older platforms, and where the flag is off and
  IOMETE_PRIVATE_DOMAINS_SET_FLAG is not true to turn it on (dev, release, a customer install).
  Admin-managed domains are covered as before by `domain-spark-settings.feature` and
  `storage/storage-browser.feature`.

  Background:
    * url baseUrl
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    # private domains arrived in 4.0.3; builds from main count as newer
    * if (!platformAtLeast('4.0.3')) karate.log('platform ' + platformVersion + ' predates private domains, skipping')
    * if (!platformAtLeast('4.0.3')) karate.abort()
    # with the flag off and not allowed to change (dev, release, a customer install), skip; where the
    # run may turn it on (all-in-one, e2e) and it still is not on, fail, so lost coverage shows
    # a target that does not know the flag (a build from before it) skips too
    * def privateDomainsFlag = karate.callSingle('classpath:iomete/helpers/settings/enable-private-domains.feature')
    * def privateDomainsOn = privateDomainsFlag.enabled
    * if (!privateDomainsOn && privateDomainsFlag.flagKnown && java.lang.System.getenv('IOMETE_PRIVATE_DOMAINS_SET_FLAG') == 'true') karate.fail('IOMETE_PRIVATE_DOMAINS_SET_FLAG is true, but the privateDomains rollout flag could not be turned on')
    * def flagOffReason = privateDomainsFlag.flagKnown ? 'the privateDomains rollout flag is off, and IOMETE_PRIVATE_DOMAINS_SET_FLAG is not true, so it is not turned on' : 'this target does not know the privateDomains rollout flag, or it is off and IOMETE_PRIVATE_DOMAINS_SET_FLAG is not true'
    * if (!privateDomainsOn) karate.log(flagOffReason, '- skipping')
    * if (!privateDomainsOn) karate.abort()

  Scenario: a member of a private domain reads its catalog and browses storage, a platform admin cannot
    The owner's catalog carries placeholder keys, since creating one never contacts storage, so the
    storage browser walks the built-in spark_catalog, which every domain may read. A platform
    admin is refused on every call twice: outside the domain, and again as a member, since only an
    owner gets past the private-domain check.

    # storage differs per environment, so the location is derived from the built-in catalog
    Given path 'api/v1/admin/spark/settings/catalogs'
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * match builtIn == '#notnull'
    * def builtInDir = builtIn.lakehouseDir
    * if (!/^s3a?:\/\//.test(builtInDir)) { karate.log('spark_catalog is not on S3 (' + builtInDir + '), the storage browser cannot list it: skipping'); karate.abort() }
    * def bucket = builtInDir.replace(/^s3a?:\/\//, '').split('/')[0]
    * def prefix = builtInDir.replace(/^s3a?:\/\/[^\/]+\/?/, '').replace(/\/*$/, '')
    * def prefix = prefix ? prefix + '/' : ''

    # per attempt: a deleted domain keeps its id reserved, and a retry runs under the same run id
    * def suffix = java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)
    * def privateDomain = 'karate-priv-' + runId + '-' + suffix
    * def catalogName = 'karate_priv_' + runId + '_' + suffix
    * def ownerUser = 'karate-priv-owner-' + runId
    * def memberUser = 'karate-priv-member-' + runId
    * def settingsPath = 'api/v1/domains/' + privateDomain + '/spark/settings'
    * def browserPath = 'api/v1/domains/' + privateDomain + '/s3-browser/spark_catalog'
    * def ownerHeaders = null

    # teardown: the catalog first and as the owner, since no admin can delete a private domain's
    # catalog, then the domain and the users. Every step runs, and one failure fails the run.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var errors = [];
        var step = function(label, fn) { try { fn(); } catch (e) { errors.push(label + ': ' + e); } };
        step('catalog', function() {
          if (!ownerHeaders) return;
          var res = karate.http(baseUrl + '/' + settingsPath + '/catalogs/' + catalogName).headers(ownerHeaders).delete();
          if (res.status != 204 && res.status != 200 && res.status != 404) throw 'HTTP ' + res.status;
        });
        step('domain', function() {
          var res = karate.http(baseUrl + '/api/v1/admin/domains/' + privateDomain).headers(adminHeaders).delete();
          if (res.status != 204 && res.status != 400 && res.status != 404) throw 'HTTP ' + res.status;
        });
        [ownerUser, memberUser].forEach(function(u) {
          step('user ' + u, function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: u }); });
        });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    * def priv = call read('classpath:iomete/helpers/domain/create-private-domain.feature') { domainId: '#(privateDomain)', owner: '#(ownerUser)' }
    * def ownerHeaders = priv.ownerHeaders
    * def clearedMember = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(memberUser)' }
    * def createdMember = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(memberUser)' }
    Given path 'api/v1/user'
    When method get
    Then status 200
    * def adminUser = response.username

    # the owner creates the domain's catalog and adds the member
    * configure headers = ownerHeaders
    * def catalogDir = builtInDir.replace(/\/+$/, '') + '/' + catalogName
    * def catalogRequest =
      """
      {
        name: '#(catalogName)',
        description: 'managed by iomete/tests/catalog/private-domain-catalog-reads.feature',
        lakehouseDir: '#(catalogDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' },
        credentials: { accessKey: 'karate-placeholder-access-key', secretKey: 'karate-placeholder-secret-key' }
      }
      """
    Given path settingsPath, 'catalogs'
    And request catalogRequest
    When method post
    Then status 200
    Given path 'api/v1/domains', privateDomain, 'members'
    And request [ { type: 'USER', value: '#(memberUser)' } ]
    When method post
    Then status 204

    * def queryOf = function(params) { if (!params) return ''; return '?' + Object.keys(params).map(k => k + '=' + java.net.URLEncoder.encode(params[k], 'UTF-8')).join('&') }
    * def statusOf = function(path, headers, params) { var res = karate.http(baseUrl + '/' + path + queryOf(params)).headers(headers).get(); return { status: res.status, body: karate.toString(res.body) } }
    # parentheses make the list JS, so the paths are evaluated rather than kept as text
    * def calls = ([ { path: settingsPath + '/catalogs' }, { path: settingsPath + '/catalogs/' + catalogName }, { path: browserPath + '/buckets' }, { path: browserPath + '/list', params: { bucket: bucket, prefix: prefix } } ])

    # the member reads the catalog the owner created. A new member's domains are cached for a
    # few seconds, so the first read waits that out
    * def memberLogin = call read('classpath:iomete/helpers/user/login.feature') { username: '#(memberUser)', password: '#(createdMember.temporaryPassword)' }
    * def memberHeaders = { Authorization: '#("Bearer " + memberLogin.accessToken)' }
    * configure headers = memberHeaders
    * configure retry = { count: 15, interval: 2000 }
    Given path settingsPath, 'catalogs'
    And retry until responseStatus != 403
    When method get
    Then status 200
    And match response.items[*].name contains catalogName

    Given path settingsPath, 'catalogs', catalogName
    When method get
    Then status 200
    And match response contains { name: '#(catalogName)', ownerDomainId: '#(privateDomain)' }
    And match response.credentials.secretKey == '********'

    Given path browserPath, 'buckets'
    When method get
    Then status 200
    And match response contains bucket

    Given path browserPath, 'list'
    And params { bucket: '#(bucket)', prefix: '#(prefix)' }
    When method get
    Then status 200
    And match response.bucketName == bucket

    # a platform admin outside the domain is refused on every call
    * def refusedAdmin = karate.map(calls, c => ({ path: c.path, status: statusOf(c.path, adminHeaders, c.params).status }))
    * match each refusedAdmin contains { status: 403 }
    # karate.http leaves its URL on the scenario's request, so the calls above need it reset
    * url baseUrl

    # and so is one the owner made a member: only an owner passes the private-domain check. The admin's
    # domain list is cached for a few seconds, so wait until the private-domain check is what answers
    * configure headers = ownerHeaders
    Given path 'api/v1/domains', privateDomain, 'members'
    And request [ { type: 'USER', value: '#(adminUser)' } ]
    When method post
    Then status 204
    * def privateAnswer = function(c) { return statusOf(c.path, adminHeaders, c.params) }
    * def waitPrivateAnswer = function(c) { for (var i = 0; i < 15; i++) { var r = privateAnswer(c); if (r.status != 403 || r.body.indexOf('private') >= 0) return r; java.lang.Thread.sleep(2000) } return privateAnswer(c) }
    * def refusedMemberAdmin = karate.map(calls, c => { var r = waitPrivateAnswer(c); return { path: c.path, status: r.status, isPrivate: r.body.indexOf('private') >= 0 } })
    * match each refusedMemberAdmin contains { status: 403, isPrivate: true }
