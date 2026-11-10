@ignore
Feature: Iceberg catalog the maintenance tests configure, invoked once per run via karate.callSingle.
  The platform refuses to configure maintenance on spark_catalog, and that is the only catalog every
  environment is guaranteed to have, so the suite brings its own. The domain-scoped maintenance API
  also rejects a catalog its domain does not own, which is why the domain is granted access and then
  made the owner. A new catalog also has no data-access policy, so nobody, admin included, can
  create anything in it until one exists; the setup adds the same allow-all the platform ships for
  spark_catalog, on this run's catalog only. Returns: catalogName.

  Scenario: get or create the maintenance catalog and make the domain its owner
    * karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domain })

    * def catalogName = fixtures.maintenanceCatalog
    * def catalogsPath = 'api/v1/admin/spark/settings/catalogs'

    # Storage differs per environment (dev is S3, release is MinIO), so the location is derived from
    # the built-in catalog instead of pinning a bucket here.
    Given url baseUrl
    And path catalogsPath
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    And match builtIn == '#notnull'
    * def lakehouseDir = builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + catalogName

    # create if missing, 409 means an earlier run already made it
    * def createRequest =
      """
      {
        name: '#(catalogName)',
        description: 'catalog for iomete-api-testing-suite, managed by iomete/tests/maintenance/setup/maintenance-catalog.feature',
        lakehouseDir: '#(lakehouseDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' }
      }
      """
    Given url baseUrl
    And path catalogsPath
    And request createRequest
    When method post
    Then assert responseStatus == 200 || responseStatus == 409

    # granting a domain that already has access errors, so only grant when it is missing
    Given url baseUrl
    And path catalogsPath, catalogName, 'permissions'
    When method get
    Then status 200
    * if (!response.includes(domain)) karate.call('classpath:iomete/helpers/catalog/grant-catalog-to-domain.feature', { catalogName: catalogName, domain: domain })

    # ownership is what the domain-scoped maintenance endpoints check, and it can only be set once
    # the domain has access. Re-setting the same owner is a no-op, so this needs no guard.
    Given url baseUrl
    And path catalogsPath, catalogName, 'owner'
    And request { domainId: '#(domain)' }
    When method put
    Then status 200

    # the platform's own default policy grants this on spark_catalog.* and nothing else
    * def catalogDatabases = catalogName + '.*'
    * def accessPolicy =
      """
      {
        name: '#(fixtures.maintenancePolicy)',
        description: 'iomete-api-testing-suite: access to the maintenance catalog of one run',
        resources: [ { databases: ['#(catalogDatabases)'], tables: ['*'], columns: ['*'] } ],
        allowPolicyItems: [ { users: ['{USER}'], accesses: ['ALL'] } ]
      }
      """
    * def created = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'access', policy: '#(accessPolicy)' }
