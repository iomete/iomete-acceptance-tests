@lock=api
Feature: Private domain data security policies, the domain's owners manage them

  A private domain keeps its own data security policies, managed through the domain API by its
  owners, on catalogs the domain owns. Each scenario runs as the owner of a fresh private domain
  with a catalog of its own: one for access policies, one for mask and row filter policies.

  The domain policy API ships in 4.0.3, and private domains can only be created with the
  `privateDomains` rollout flag on, so both scenarios skip on older platforms and where it is off.

  Not tested here: the refusals (a catalog the domain does not own, another domain's policy,
  an admin-managed domain). They stay in iom-identity's tests.

  Background:
    * url baseUrl
    * if (!platformAtLeast('4.0.3')) { karate.log('domain data security policies need 4.0.3: skipping'); karate.abort() }
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    * def rollout = call read('classpath:iomete/helpers/settings/rollout-flags.feature')
    * if (rollout.flags.privateDomains != true) { karate.log('the privateDomains rollout flag is off, private domains cannot be created: skipping'); karate.abort() }

    # storage differs per environment, so the location is derived from the built-in catalog
    Given path 'api/v1/admin/spark/settings/catalogs'
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * match builtIn == '#notnull'

    # per attempt: a deleted domain keeps its id reserved, and a retry runs under the same run id
    * def suffix = java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)
    * def privateDomain = 'karate-dsp-' + runId + '-' + suffix
    * def ownerUser = 'karate-dsp-owner-' + runId + '-' + suffix
    * def catalogName = 'karate_dsp_' + runId + '_' + suffix
    * def policyName = 'karate-dsp-' + runId + '-' + suffix
    * def settingsPath = 'api/v1/domains/' + privateDomain + '/spark/settings'
    * def policiesPath = 'api/v1/domains/' + privateDomain + '/data-security'
    * def ownerHeaders = null
    # what the owner created, newest last; only the owner can delete it
    * def created = []

    # teardown: the owner's policies and catalog, newest first, then the domain and the owner
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var errors = [];
        var del = function(path, headers) {
          var res = karate.http(baseUrl + '/' + path).headers(headers).delete();
          if (res.status != 200 && res.status != 204 && res.status != 404) errors.push(path + ': HTTP ' + res.status);
        };
        created.slice().reverse().forEach(function(path) { del(path, ownerHeaders); });
        del('api/v1/admin/domains/' + privateDomain, adminHeaders);
        karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: ownerUser });
        if (errors.length > 0) karate.fail('teardown left state behind: ' + errors.join('; '));
      }
      """

    * def priv = call read('classpath:iomete/helpers/domain/create-private-domain.feature') { domainId: '#(privateDomain)', owner: '#(ownerUser)' }
    * def ownerHeaders = priv.ownerHeaders
    * configure headers = ownerHeaders

    # a policy can only name catalogs the domain owns. Placeholder keys: saving a catalog never contacts storage
    * def lakehouseDir = builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + catalogName
    Given path settingsPath, 'catalogs'
    And request
      """
      {
        name: '#(catalogName)',
        description: 'managed by iomete/tests/data-security/domain-policies.feature',
        lakehouseDir: '#(lakehouseDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' },
        credentials: { accessKey: 'karate-placeholder-access-key', secretKey: 'karate-placeholder-secret-key' }
      }
      """
    When method post
    Then status 200
    * created.push(settingsPath + '/catalogs/' + catalogName)
    And match response.ownerDomainId == privateDomain

  Scenario: a private domain's owner creates, reads, updates and deletes an access policy

    * def databases = ([ catalogName + '.*' ])
    * def policy =
      """
      {
        name: '#(policyName)',
        description: 'managed by iomete/tests/data-security/domain-policies.feature',
        resources: [ { databases: '#(databases)', tables: ['*'], columns: ['*'] } ],
        allowPolicyItems: [ { users: ['#(priv.owner)'], groups: [], accesses: ['SELECT'] } ]
      }
      """
    Given path policiesPath, 'access-policies'
    And request policy
    When method post
    Then status 201
    * def policyId = response.id
    * created.push(policiesPath + '/access-policies/' + policyId)
    And match response contains { name: '#(policyName)' }

    Given path policiesPath, 'access-policies'
    When method get
    Then status 200
    And match response[*].name contains policyName

    * set policy.allowPolicyItems[0].accesses = ['SELECT', 'INSERT']
    Given path policiesPath, 'access-policies', policyId
    And request policy
    When method put
    Then status 200

    Given path policiesPath, 'access-policies', policyId
    When method get
    Then status 200
    And match response.allowPolicyItems[0].accesses contains only ['SELECT', 'INSERT']

    Given path policiesPath, 'access-policies', policyId
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200
    Given path policiesPath, 'access-policies', policyId
    When method get
    Then status 404

  Scenario: a private domain's owner creates, updates and deletes a mask and a row filter policy
    Both go through the same endpoints as access policies, under their own type's path.

    * def database = catalogName + '.karate_db'
    * def maskName = policyName + '-mask'
    * def mask =
      """
      {
        name: '#(maskName)',
        resources: [ { database: '#(database)', table: 'customers', column: 'email' } ],
        dataMaskPolicyItems: [ { dataMaskType: 'MASK_HASH', users: ['#(priv.owner)'] } ]
      }
      """
    Given path policiesPath, 'mask-policies'
    And request mask
    When method post
    Then status 201
    * def maskId = response.id
    * created.push(policiesPath + '/mask-policies/' + maskId)

    * set mask.dataMaskPolicyItems[0].dataMaskType = 'MASK_NULL'
    Given path policiesPath, 'mask-policies', maskId
    And request mask
    When method put
    Then status 200

    Given path policiesPath, 'mask-policies', maskId
    When method get
    Then status 200
    And match response contains { name: '#(maskName)' }
    And match response.dataMaskPolicyItems[0].dataMaskType == 'MASK_NULL'

    * def filterName = policyName + '-filter'
    * def filter =
      """
      {
        name: '#(filterName)',
        resources: [ { database: '#(database)', table: 'customers' } ],
        rowFilterPolicyItems: [ { filterExpr: "country = 'US'", users: ['#(priv.owner)'] } ]
      }
      """
    Given path policiesPath, 'row-filter-policies'
    And request filter
    When method post
    Then status 201
    * def filterId = response.id
    * created.push(policiesPath + '/row-filter-policies/' + filterId)

    * set filter.rowFilterPolicyItems[0].filterExpr = "country = 'DE'"
    Given path policiesPath, 'row-filter-policies', filterId
    And request filter
    When method put
    Then status 200

    Given path policiesPath, 'row-filter-policies', filterId
    When method get
    Then status 200
    And match response.rowFilterPolicyItems[0].filterExpr == "country = 'DE'"

    Given path policiesPath, 'mask-policies', maskId
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200
    Given path policiesPath, 'mask-policies', maskId
    When method get
    Then status 404
    Given path policiesPath, 'row-filter-policies', filterId
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200
    Given path policiesPath, 'row-filter-policies', filterId
    When method get
    Then status 404
