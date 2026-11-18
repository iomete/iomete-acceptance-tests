@lock=api
Feature: Private domain catalogs, the domain's owners create, test and delete them

  A private domain manages its own catalogs through the domain API, and only its own owners
  may: no platform admin role counts as one there. One journey as the owner of a fresh private
  domain, and one check that an admin-managed domain does not offer these endpoints at all.

  Private domains arrived in 4.0.3 and can only be created with the `privateDomains` rollout
  flag on, so both scenarios skip on older platforms, and where the flag is off and
  IOMETE_PRIVATE_DOMAINS_SET_FLAG is not true to turn it on (dev, release, a customer install).

  Not tested here: the refused catalog types, endpoints and properties, and the rules for
  updating a private domain's catalog. They stay in iom-core's tests.

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

    # storage differs per environment, so the location is derived from the built-in catalog
    Given path 'api/v1/admin/spark/settings/catalogs'
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * match builtIn == '#notnull'
    # per attempt: a deleted domain keeps its id reserved, and a retry runs under the same run id
    * def suffix = java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)
    * def catalogName = 'karate_priv_' + runId + '_' + suffix
    # placeholder keys: creating a catalog never contacts storage
    * def catalogRequest =
      """
      function(name) {
        return {
          name: name,
          description: 'managed by iomete/tests/catalog/private-domain-catalogs.feature',
          lakehouseDir: builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + name,
          catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' },
          credentials: { accessKey: 'karate-placeholder-access-key', secretKey: 'karate-placeholder-secret-key' }
        };
      }
      """

  Scenario: a private domain's owner checks, creates, reads back and deletes a catalog
    The catalog carries placeholder keys. The connection check uses only the keys it is sent, never
    the platform's own storage access, so it must fail to write. A platform admin is refused
    twice: outside the domain, and as a member, since membership does not make an owner. The
    built-in spark_catalog is not the domain's to delete.

    * def privateDomain = 'karate-priv-' + runId + '-' + suffix
    * def ownerUser = 'karate-priv-owner-' + runId
    * def settingsPath = 'api/v1/domains/' + privateDomain + '/spark/settings'
    * def ownerHeaders = null

    # teardown: the catalog first and as the owner, since no admin can delete a private domain's
    # catalog, then the domain and the owner. Every step runs, and one failure fails the run.
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
        step('owner', function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: ownerUser }); });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    * def priv = call read('classpath:iomete/helpers/domain/create-private-domain.feature') { domainId: '#(privateDomain)', owner: '#(ownerUser)' }
    * def ownerHeaders = priv.ownerHeaders
    * def body = catalogRequest(catalogName)

    * configure headers = ownerHeaders
    Given path settingsPath, 'catalog-connection-check'
    And request body
    When method post
    Then status 200
    * def check = { success: '#boolean', errorMessage: '##string' }
    And match response == { List: '#(check)', Write: '#(check)', Read: '#(check)', Delete: '#(check)' }
    And match response.Write.success == false

    Given path settingsPath, 'catalogs'
    And request body
    When method post
    Then status 200
    And match response contains { name: '#(catalogName)', ownerDomainId: '#(privateDomain)' }
    And match response.credentials.secretKey == '********'

    Given path settingsPath, 'catalogs', catalogName
    When method get
    Then status 200
    And match response contains { name: '#(catalogName)', ownerDomainId: '#(privateDomain)', lakehouseDir: '#(body.lakehouseDir)' }

    # a platform admin outside the domain is refused
    * configure headers = adminHeaders
    Given path settingsPath, 'catalogs', catalogName
    When method delete
    Then status 403

    # and so is one the owner made a member: only the domain's own owners manage its catalogs.
    # The admin's domain list is cached for a few seconds, so wait for the owner rule's answer
    Given path 'api/v1/user'
    When method get
    Then status 200
    * def adminUser = response.username
    * configure headers = ownerHeaders
    Given path 'api/v1/domains', privateDomain, 'members'
    And request [ { type: 'USER', value: '#(adminUser)' } ]
    When method post
    Then status 204

    * configure headers = adminHeaders
    * configure retry = { count: 15, interval: 2000 }
    Given path settingsPath, 'catalogs', catalogName
    And retry until responseStatus != 403 || karate.toString(response).indexOf('Only owners') >= 0
    When method delete
    Then status 403
    And match karate.toString(response) contains 'Only owners'
    # the name is taken, so a create that got past the owner rule would answer 409, not 403
    Given path settingsPath, 'catalogs'
    And request body
    When method post
    Then status 403

    * configure headers = ownerHeaders
    Given path settingsPath, 'catalogs', 'spark_catalog'
    When method delete
    Then status 403

    Given path settingsPath, 'catalogs', catalogName
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200
    Given path settingsPath, 'catalogs', catalogName
    When method get
    Then status 404

  Scenario: an admin-managed domain does not manage its own catalogs
    Create, check and delete answer 404 in a domain that is not private, so installs without
    private domains keep managing catalogs through the admin API. The run's own domain is admin-managed.

    * def settingsPath = 'api/v1/domains/' + domain + '/spark/settings'
    # a create that got through would leave a catalog the admin can still delete
    * configure afterScenario = function() { karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: catalogName }) }

    Given path settingsPath, 'catalogs'
    And request catalogRequest(catalogName)
    When method post
    Then status 404

    Given path settingsPath, 'catalog-connection-check'
    And request catalogRequest(catalogName)
    When method post
    Then status 404

    Given path settingsPath, 'catalogs', 'spark_catalog'
    When method delete
    Then status 404
