@lock=api
Feature: Admin catalog API with a private domain's catalog, which it treats as missing

  A catalog owned by a private domain belongs to that domain's owners alone. The admin catalog
  API acts as if it does not exist, and never hands a global catalog to a private domain. One
  journey over a catalog the domain's owner creates, and one over a global catalog an admin tries
  to give to the domain. Admin work on global catalogs stays in `catalog-admin-actions.feature`.

  Private domains arrived in 4.0.3 and can only be created with the `privateDomains` rollout
  flag on, so both scenarios skip on older platforms, and where the flag is off and
  IOMETE_PRIVATE_DOMAINS_SET_FLAG is not true to turn it on (dev, release, a customer install).

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

    * def catalogsPath = 'api/v1/admin/spark/settings/catalogs'
    # storage differs per environment, so the location is derived from the built-in catalog
    Given path catalogsPath
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * match builtIn == '#notnull'
    # per attempt: a deleted domain keeps its id reserved, and a retry runs under the same run id
    * def suffix = java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)
    * def privateDomain = 'karate-priv-' + runId + '-' + suffix
    * def ownerUser = 'karate-priv-owner-' + runId
    * def domainSettingsPath = 'api/v1/domains/' + privateDomain + '/spark/settings'
    * def catalogBody =
      """
      function(name) {
        return {
          name: name,
          description: 'managed by iomete/tests/catalog/private-domain-admin-catalogs.feature',
          lakehouseDir: builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + name,
          catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' },
          credentials: { accessKey: 'karate-placeholder-access-key', secretKey: 'karate-placeholder-secret-key' }
        };
      }
      """
    * def ownerHeaders = null
    * def privateCatalog = null
    * def globalCatalog = null

    # teardown: the private domain's catalog as its owner (no admin can delete it), the global
    # catalog, the domain and the owner. Every step runs, and one failure fails the run.
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var errors = [];
        var step = function(label, fn) { try { fn(); } catch (e) { errors.push(label + ': ' + e); } };
        step('private catalog', function() {
          if (!ownerHeaders || !privateCatalog) return;
          var res = karate.http(baseUrl + '/' + domainSettingsPath + '/catalogs/' + privateCatalog).headers(ownerHeaders).delete();
          if (res.status != 204 && res.status != 200 && res.status != 404) throw 'HTTP ' + res.status;
        });
        step('global catalog', function() {
          if (globalCatalog) karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: globalCatalog });
        });
        step('domain', function() {
          var res = karate.http(baseUrl + '/api/v1/admin/domains/' + privateDomain).headers(adminHeaders).delete();
          if (res.status != 204 && res.status != 400 && res.status != 404) throw 'HTTP ' + res.status;
        });
        step('owner', function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: ownerUser }); });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    * def priv = call read('classpath:iomete/helpers/domain/create-private-domain.feature') { domainId: '#(privateDomain)', owner: '#(ownerUser)' }
    * def ownerHeaders = priv.ownerHeaders

  Scenario: the admin catalog API answers for a private domain's catalog as for a missing one
    Both catalog lists leave it out, and every admin call naming it answers with the status and body
    the same call gets for a catalog that never existed. The bulk grant stores rows for a missing
    catalog unchecked, so for a hidden one it only has to refuse with 404. A create of the same name
    gets the generic conflict.

    * def privateCatalog = 'karate_priv_' + runId + '_' + suffix
    * def missingCatalog = 'karate_priv_none_' + runId + '_' + suffix
    * configure headers = ownerHeaders
    Given path domainSettingsPath, 'catalogs'
    And request catalogBody(privateCatalog)
    When method post
    Then status 200
    * configure headers = adminHeaders

    # every answer is collected first and checked at the end, so one failing check still shows the rest
    Given path catalogsPath
    When method get
    Then status 200
    * def listedNames = response.items.map(c => c.name)
    Given path catalogsPath, 'domain', privateDomain, 'permissions'
    When method get
    Then status 200
    * def domainCatalogs = response

    # each admin call, sent for the hidden catalog and for one that never existed, compared with
    # the name taken out of both bodies
    * def send =
      """
      function(c, name) {
        var req = karate.http(baseUrl + '/' + catalogsPath + '/' + name + c.path).headers(adminHeaders);
        var res = c.method == 'get' ? req.get() : c.method == 'delete' ? req.delete() : c.method == 'put' ? req.put(c.body(name)) : req.post(c.body(name));
        return { status: res.status, body: karate.toString(res.body).split(name).join('<catalog>') };
      }
      """
    * def calls =
      """
      ([
        { what: 'get', method: 'get', path: '' },
        { what: 'update', method: 'put', path: '', body: function(n) { return catalogBody(n) } },
        { what: 'delete', method: 'delete', path: '' },
        { what: 'list permissions', method: 'get', path: '/permissions' },
        { what: 'grant', method: 'post', path: '/permissions', body: function(n) { return { domains: [domain] } } },
        { what: 'revoke', method: 'delete', path: '/permissions/' + domain },
        { what: 'set owner', method: 'put', path: '/owner', body: function(n) { return { domainId: domain } } },
        { what: 'clear owner', method: 'delete', path: '/owner' },
        { what: 'properties', method: 'put', path: '/properties', body: function(n) { return { upsertedProperties: [ { key: 'karate.edited', value: 'yes' } ], deletedPropertyKeys: [] } } },
        { what: 'resource tags', method: 'put', path: '/resource-tags', body: function(n) { return { resourceTags: [ { key: 'usage', value: 'acceptance' } ] } } }
      ])
      """
    * def answers = karate.map(calls, c => ({ what: c.what, hidden: send(c, privateCatalog), missing: send(c, missingCatalog) }))
    * karate.forEach(answers, a => karate.log(a.what + ': hidden ' + a.hidden.status + ' ' + a.hidden.body + ' | missing ' + a.missing.status + ' ' + a.missing.body))

    # karate.http leaves its URL on the scenario's request, so the calls above need it reset
    * url baseUrl

    # the bulk grant stores rows for a missing catalog without checking, so there is no missing answer
    # to compare with: a hidden catalog only has to be refused, without naming its domain
    Given path catalogsPath, 'permissions', 'bulk'
    And request [ { catalogName: '#(privateCatalog)', domains: ['#(domain)'] } ]
    When method post
    * def bulk = { status: '#(responseStatus)', body: '#(karate.toString(response).split(privateCatalog).join("<catalog>"))' }
    * karate.log('bulk grant: hidden ' + bulk.status + ' ' + bulk.body)

    # a create of the same name meets the generic conflict, which does not name the owner domain
    Given path catalogsPath
    And request catalogBody(privateCatalog)
    When method post
    * def conflict = { status: '#(responseStatus)', body: '#(karate.toString(response))' }
    * karate.log('create of the same name: ' + conflict.status + ' ' + conflict.body)

    * match listedNames !contains privateCatalog
    * match domainCatalogs !contains privateCatalog
    * def differing = answers.filter(a => a.hidden.status != a.missing.status || a.hidden.body != a.missing.body).map(a => a.what)
    * match differing == []
    * match bulk.status == 404
    * match bulk.body !contains privateDomain
    * match conflict.status == 409
    * match conflict.body !contains privateDomain

    # none of it touched the catalog: its owner still reads it as before
    * configure headers = ownerHeaders
    Given path domainSettingsPath, 'catalogs', privateCatalog
    When method get
    Then status 200
    And match response contains { name: '#(privateCatalog)', ownerDomainId: '#(privateDomain)', description: '#(catalogBody(privateCatalog).description)' }
    And match response.properties !contains { key: 'karate.edited', value: 'yes' }

  Scenario: an admin cannot give a global catalog to a private domain
    A private domain only reaches storage through its own catalogs and the built-in one, so
    granting it a global catalog, one at a time or in bulk, and making it the owner are refused.

    * def globalCatalog = 'karate_priv_global_' + runId + '_' + suffix
    * def deleted = call read('classpath:iomete/helpers/catalog/delete-catalog.feature') { catalogName: '#(globalCatalog)' }
    * def globalBody = catalogBody(globalCatalog)
    * remove globalBody.credentials
    Given path catalogsPath
    And request globalBody
    When method post
    Then status 200

    Given path catalogsPath, globalCatalog, 'permissions'
    And request { domains: ['#(privateDomain)'] }
    When method post
    Then status 403

    Given path catalogsPath, 'permissions', 'bulk'
    And request [ { catalogName: '#(globalCatalog)', domains: ['#(privateDomain)'] } ]
    When method post
    Then status 403

    Given path catalogsPath, globalCatalog, 'owner'
    And request { domainId: '#(privateDomain)' }
    When method put
    Then status 403

    Given path catalogsPath, globalCatalog
    When method get
    Then status 200
    And match response.ownerDomainId == '##null'
    Given path catalogsPath, globalCatalog, 'permissions'
    When method get
    Then status 200
    And match response !contains privateDomain
