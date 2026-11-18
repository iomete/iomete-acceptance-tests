@lock=api
Feature: Private domain tag policies, the domain's owners tag its columns and manage its tag policies

  A private domain keeps its own tag policies, such as "mask every PII column", managed through the
  domain API by its owners and out of the admin's reach. One journey on a fresh private domain with
  a catalog of its own.

  The domain tag policy API ships in 4.0.3, and private domains can only be created with
  the `privateDomains` rollout flag on, so the scenario skips on older platforms and where it is off.

  Not tested here: that a domain tag policy masks a query in the domain's catalogs and not in a
  global one. That needs a compute inside a private domain, which needs a namespace no other domain
  holds and storage keys of the domain's own. The refusals (a non-owner, an admin-managed domain,
  another domain's catalog) stay in iom-identity's and iom-catalog's tests.

  Background:
    * url baseUrl
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    * if (!platformAtLeast('4.0.3-rc3')) { karate.log('domain tag policies need 4.0.3-rc3: skipping'); karate.abort() }
    * def privateDomainsFlag = karate.callSingle('classpath:iomete/helpers/settings/enable-private-domains.feature')
    * if (!privateDomainsFlag.enabled && privateDomainsFlag.flagKnown && java.lang.System.getenv('IOMETE_PRIVATE_DOMAINS_SET_FLAG') == 'true') karate.fail('IOMETE_PRIVATE_DOMAINS_SET_FLAG is true, but the privateDomains rollout flag could not be turned on')
    * if (!privateDomainsFlag.enabled) { karate.log('private domains cannot be created on this target: skipping'); karate.abort() }

  Scenario: a private domain's owner tags a column and manages a tag mask and a tag access policy the admin never sees
    The owner's tag change applies at once, with no admin review, and the admin's tag asset list
    leaves the column out. Both policies name the run's tag, and neither shows in the admin's tag
    policy lists. Tags are platform-wide, so the admin creates the tag and deletes it afterwards.

    # storage differs per environment, so the location is derived from the built-in catalog
    Given path 'api/v1/admin/spark/settings/catalogs'
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * match builtIn == '#notnull'

    # per attempt: a deleted domain keeps its id reserved, and a retry runs under the same run id
    * def suffix = java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)
    * def privateDomain = 'karate-priv-' + runId + '-' + suffix
    * def ownerUser = 'karate-priv-owner-' + runId
    * def catalogName = 'karate_dtp_' + runId + '_' + suffix
    * def tagName = 'karate-dtp-pii-' + runId + '-' + suffix
    * def maskName = 'karate-dtp-mask-' + runId + '-' + suffix
    * def accessName = 'karate-dtp-access-' + runId + '-' + suffix
    * def settingsPath = 'api/v1/domains/' + privateDomain + '/spark/settings'
    * def policiesPath = 'api/v1/domains/' + privateDomain + '/data-security'
    * def requestsPath = 'api/v1/domains/' + privateDomain + '/governance/classification-requests'
    * def column = { catalogName: '#(catalogName)', schemaName: 'karate_db', tableName: 'customers', columnName: 'email', tagName: '#(tagName)' }
    # what the scenario made, removed in reverse in the teardown
    * def made = { ownerHeaders: null, created: [], tagged: false, tagId: null }

    # teardown: the policies and the tag on the column go as the owner, since no admin can remove
    # them, then the catalog, the domain, the owner and the tag. Every step runs, and one failure fails the run.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var errors = [];
        var step = function(label, fn) { try { fn(); } catch (e) { errors.push(label + ': ' + e); } };
        var del = function(path, headers) {
          var res = karate.http(baseUrl + '/' + path).headers(headers).delete();
          if (res.status != 200 && res.status != 204 && res.status != 404) throw 'HTTP ' + res.status;
        };
        made.created.slice().reverse().forEach(function(path) { step(path, function() { del(path, made.ownerHeaders); }); });
        step('untag', function() {
          if (!made.tagged) return;
          var res = karate.http(baseUrl + '/' + requestsPath).headers(made.ownerHeaders).post(karate.merge(column, { requestType: 'REMOVE' }));
          if (res.status != 201) throw 'HTTP ' + res.status + ' ' + karate.toString(res.body);
        });
        step('catalog', function() { if (made.ownerHeaders) del(settingsPath + '/catalogs/' + catalogName, made.ownerHeaders); });
        step('domain', function() {
          var res = karate.http(baseUrl + '/api/v1/admin/domains/' + privateDomain).headers(adminHeaders).delete();
          if (res.status != 204 && res.status != 400 && res.status != 404) throw 'HTTP ' + res.status;
        });
        step('user ' + ownerUser, function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: ownerUser }); });
        step('tag', function() { if (made.tagId) karate.call('classpath:iomete/helpers/security/delete-tag.feature', { tagId: made.tagId }); });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    # the admin creates the tag, which is platform-wide
    * def tag = call read('classpath:iomete/helpers/security/ensure-tag.feature') { tagName: '#(tagName)' }
    * eval made.tagId = tag.tagId

    * def priv = call read('classpath:iomete/helpers/domain/create-private-domain.feature') { domainId: '#(privateDomain)', owner: '#(ownerUser)' }
    * def ownerHeaders = priv.ownerHeaders
    * eval made.ownerHeaders = ownerHeaders
    * configure headers = ownerHeaders

    # a domain can only tag and write policies for catalogs it owns. Placeholder keys: saving a catalog never contacts storage
    * def lakehouseDir = builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + catalogName
    Given path settingsPath, 'catalogs'
    And request
      """
      {
        name: '#(catalogName)',
        description: 'managed by iomete/tests/data-security/domain-tag-policies.feature',
        lakehouseDir: '#(lakehouseDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' },
        credentials: { accessKey: 'karate-placeholder-access-key', secretKey: 'karate-placeholder-secret-key' }
      }
      """
    When method post
    Then status 200

    # the owner tags a column of the domain's catalog, and it applies with no admin review
    Given path requestsPath
    And request karate.merge(column, { requestType: 'ADD' })
    When method post
    Then status 201
    And match response.status == 'APPROVED'
    * eval made.tagged = true

    # the admin's list of the tag's columns leaves the domain's column out
    * configure headers = adminHeaders
    Given path 'api/v1/admin/governance/classification-tags', tag.tagId, 'assets'
    When method get
    Then status 200
    * def assets = Array.isArray(response) ? response : response.items
    And match assets == []
    * configure headers = ownerHeaders

    # a tag mask: create, update, read back
    * def mask =
      """
      {
        name: '#(maskName)',
        description: 'managed by iomete/tests/data-security/domain-tag-policies.feature',
        tags: ['#(tagName)'],
        dataMaskPolicyItems: [ { dataMaskType: 'MASK_HASH', users: ['#(priv.owner)'] } ]
      }
      """
    Given path policiesPath, 'tag-mask-policies'
    And request mask
    When method post
    Then status 201
    * def maskId = response.id
    * made.created.push(policiesPath + '/tag-mask-policies/' + maskId)
    And match response contains { name: '#(maskName)', tags: ['#(tagName)'] }

    * set mask.dataMaskPolicyItems[0].dataMaskType = 'MASK_NULL'
    Given path policiesPath, 'tag-mask-policies', maskId
    And request mask
    When method put
    Then status 200

    Given path policiesPath, 'tag-mask-policies', maskId
    When method get
    Then status 200
    And match response.dataMaskPolicyItems[0].dataMaskType == 'MASK_NULL'
    And match response.tags == ['#(tagName)']

    # a tag access policy: create, list, update, read back
    * def access =
      """
      {
        name: '#(accessName)',
        description: 'managed by iomete/tests/data-security/domain-tag-policies.feature',
        tags: ['#(tagName)'],
        allowPolicyItemViews: [ { users: ['#(priv.owner)'], groups: [], accesses: ['SELECT'] } ]
      }
      """
    Given path policiesPath, 'tag-access-policies'
    And request access
    When method post
    Then status 201
    * def accessId = response.id
    * made.created.push(policiesPath + '/tag-access-policies/' + accessId)

    Given path policiesPath, 'tag-access-policies'
    When method get
    Then status 200
    And match response[*].name contains accessName

    * set access.allowPolicyItemViews[0].accesses = ['SELECT', 'INSERT']
    Given path policiesPath, 'tag-access-policies', accessId
    And request access
    When method put
    Then status 200

    Given path policiesPath, 'tag-access-policies', accessId
    When method get
    Then status 200
    And match response.allowPolicyItemViews[0].accesses contains only ['SELECT', 'INSERT']
    And match response.tags == ['#(tagName)']

    # the admin's tag policy lists show neither
    * configure headers = adminHeaders
    Given path 'api/v1/admin/data-security/tag/mask/policy'
    When method get
    Then status 200
    And match response == '#array'
    And match response[*].name !contains maskName
    Given path 'api/v1/admin/data-security/tag/access/policy'
    When method get
    Then status 200
    And match response == '#array'
    And match response[*].name !contains accessName
    * configure headers = ownerHeaders

    # the owner deletes both
    Given path policiesPath, 'tag-mask-policies', maskId
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200
    Given path policiesPath, 'tag-mask-policies', maskId
    When method get
    Then status 404
    Given path policiesPath, 'tag-access-policies', accessId
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200
    Given path policiesPath, 'tag-access-policies', accessId
    When method get
    Then status 404
