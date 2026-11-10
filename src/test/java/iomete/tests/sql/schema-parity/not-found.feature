@lock=api
Feature: SQL schema parity — a missing table, namespace or catalog answers an error

  The status a client sees for a missing table, namespace or catalog, on V1 and V2. V2 answers
  404 for all three. V1 answers 404 for a missing table and 500 for a missing namespace or
  catalog, because it wraps every listing error: an intended difference, asserted on both sides.
  The same checks on the other V2 routes (admin, with metadata, the forwarded V1 routes) run the
  same code and are left to iom-sql's tests.

  Skips when ARROW_FLIGHT_FOR_DB_EXPLORER is off: every V2 schema endpoint answers 409 then.

  Background:
    * url baseUrl
    * if (!arrowFlightDbExplorerEnabled) karate.log('ARROW_FLIGHT_FOR_DB_EXPLORER is off, V2 schema routes are not served here, skipping')
    * if (!arrowFlightDbExplorerEnabled) karate.abort()
    # route prefixes, this run's seeded database and table, and the comparison helpers
    * def ctx = karate.call('classpath:iomete/tests/sql/schema-parity/setup/parity.feature', { domain: domain })
    * def v1Native = ctx.v1Native
    * def v2 = ctx.v2
    * def catalogName = ctx.catalogName
    * def namespace = ctx.namespace
    * def errorBody = ctx.errorBody

  Scenario: a missing table, namespace or catalog answers an error, 404 on V2 where V1 wraps listings as 500
    * def missingNamespace = 'karate_parity_missing_ns_' + runId
    * def missingCatalog = 'karate_parity_missing_cat_' + runId

    # ===== 1. Missing table: 404 on both =====

    # V1 (native): describe a missing table in the seeded namespace
    Given path v1Native, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'karate_parity_missing_table'
    When method get
    Then status 404
    And match response contains errorBody

    # V2: describe a missing table in the seeded namespace
    Given path v2, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'karate_parity_missing_table'
    When method get
    Then status 404
    And match response contains errorBody

    # ===== 2. Missing namespace: V1 500, V2 404 =====

    # V1 (native): list the tables of a missing namespace
    Given path v1Native, 'catalogs', catalogName, 'namespaces', missingNamespace, 'tables'
    When method get
    Then status 500
    And match response contains errorBody

    # V2: list the tables of a missing namespace
    Given path v2, 'catalogs', catalogName, 'namespaces', missingNamespace, 'tables'
    When method get
    Then status 404
    And match response contains errorBody

    # ===== 3. Missing catalog: V1 500, V2 404 =====

    # V1 (native): list the namespaces of a missing catalog
    Given path v1Native, 'catalogs', missingCatalog, 'namespaces'
    When method get
    Then status 500
    And match response contains errorBody

    # V2: list the namespaces of a missing catalog
    Given path v2, 'catalogs', missingCatalog, 'namespaces'
    When method get
    Then status 404
    And match response contains errorBody
