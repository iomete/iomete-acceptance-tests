@lock=api
Feature: SQL schema parity — access to a catalog and to a domain

  A catalog not granted to the domain is refused with 403 on every V2 domain route, and stays
  open on the admin route, since the admin catalog list shows every catalog. A domain the caller
  has no access to is refused on V2 the way V1 refuses it, not answered with an empty list;
  membership of a real non-member user is covered by
  iom-sql's tests.

  Skips when ARROW_FLIGHT_FOR_DB_EXPLORER is off: every V2 schema endpoint answers 409 then.

  Background:
    * url baseUrl
    * if (!arrowFlightDbExplorerEnabled) karate.log('ARROW_FLIGHT_FOR_DB_EXPLORER is off, V2 schema routes are not served here, skipping')
    * if (!arrowFlightDbExplorerEnabled) karate.abort()
    # route prefixes, this run's seeded database and table, and the comparison helpers
    * def ctx = karate.call('classpath:iomete/tests/sql/schema-parity/setup/parity.feature', { domain: domain })
    * def v1Native = ctx.v1Native
    * def v2 = ctx.v2
    * def v2Admin = ctx.v2Admin
    * def catalogName = ctx.catalogName
    * def namespace = ctx.namespace
    * def errorBody = ctx.errorBody

  Scenario: a catalog attached to no domain is refused to the domain and open to the admin

    # ===== Setup: a catalog attached to no domain =====
    # scenario-owned and attached to no domain; it has no data-access policy, which a namespace
    # listing does not need
    * def soloCatalog = 'karate_parity_cat_' + runId
    * configure afterScenario = function(){ karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: soloCatalog }) }

    # iom-core admin: list all catalogs
    Given path 'api/v1/admin/spark/settings/catalogs'
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * def lakehouseDir = builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + soloCatalog

    # iom-core admin: create the catalog
    Given path 'api/v1/admin/spark/settings/catalogs'
    And request { name: '#(soloCatalog)', description: 'iomete-api-testing-suite schema-parity, attached to no domain', lakehouseDir: '#(lakehouseDir)', catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' } }
    When method post
    Then assert responseStatus == 200 || responseStatus == 409

    # ===== 1. V1: refused, wrapped as 500 =====
    # V1's `default` domain has no access either: V1 wraps that as 500

    # V1 (native): list the namespaces of the catalog attached to no domain
    Given path v1Native, 'catalogs', soloCatalog, 'namespaces'
    When method get
    Then status 500
    And match response contains errorBody

    # ===== 2. V2 domain: 403 on every route =====
    # the domain is refused on every V2 route

    # V2: list the namespaces of the catalog attached to no domain
    Given path v2, 'catalogs', soloCatalog, 'namespaces'
    When method get
    Then status 403
    And match response contains errorBody

    # V2: list every table of the catalog attached to no domain
    Given path v2, 'catalogs', soloCatalog, 'tables'
    When method get
    Then status 403
    And match response contains errorBody

    # V2: list the tables of the seeded namespace of the catalog attached to no domain
    Given path v2, 'catalogs', soloCatalog, 'namespaces', namespace, 'tables'
    When method get
    Then status 403
    And match response contains errorBody

    # V2: describe employees in the seeded namespace of the catalog attached to no domain
    Given path v2, 'catalogs', soloCatalog, 'namespaces', namespace, 'tables', 'employees'
    When method get
    Then status 403
    And match response contains errorBody

    # ===== 3. V2 admin: allowed, never 403 =====
    # the admin catalog list shows every catalog, so the admin tree must open it too: never a 403.
    # The shared schema server takes a moment to load a catalog created seconds ago, so it may
    # answer 500 at first; wait for the listing

    # V2 admin: list the namespaces of the catalog attached to no domain
    Given path v2Admin, 'catalogs', soloCatalog, 'namespaces'
    When method get
    * if (responseStatus == 403) karate.fail('admin was refused a catalog attached to no domain: ' + karate.toString(response))
    * configure retry = { count: 10, interval: 3000 }

    # V2 admin: list the namespaces of the catalog attached to no domain
    Given path v2Admin, 'catalogs', soloCatalog, 'namespaces'
    And retry until responseStatus == 200
    When method get
    Then status 200

  Scenario: a domain the caller has no access to is refused on V2, not listed as empty
    # V2 answered 200 [] here before 4.0.2
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the V2 schema fixes these checks compare, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()
    # a domain that does not exist: no caller has access to it. V1's domain route forwards to V2
    # while the flag is on, so V2 is asserted directly, the 403 V1 always gave (one route is enough)
    * def noDomain = 'karate-parity-nodomain-' + runId

    # V2: list the namespaces of the domain
    Given path 'api/v2/domains', noDomain, 'sql/schema/namespaces'
    When method get
    # 403, not just "not 200": an outage answering 500 must not pass as a refusal
    Then status 403
