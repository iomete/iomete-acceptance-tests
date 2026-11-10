@ignore
Feature: Shared context for the V1 vs V2 schema parity features

  The V1 baseline is the deprecated `api/v1/schema/...` routes: they always run iom-cluster's
  native code. The domain and admin V1 routes forward to V2 while ARROW_FLIGHT_FOR_DB_EXPLORER
  is on, so the features check those answer exactly what V2 answers rather than use them as a
  baseline. The deprecated routes always use the `default` domain, which can read
  `spark_catalog`, so the objects compared live there: this run's seeded database and its
  employees table. Returns the route prefixes, the seeded names and the helpers below.

  Scenario: seed once per run and return the shared context
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def computeName = testData.computeName
    * def catalogName = testData.database.split('.')[0]
    * def namespace = testData.database.split('.')[1]
    # V1 baseline: the deprecated routes, always iom-cluster's native code, `default` domain
    * def v1Native = 'api/v1/schema'
    # the V1 URL customers call: answers from V2 while forwarding is on (setup/v1-forwarding.feature),
    # from V1's own code otherwise
    * def v1Forwarded = 'api/v1/domains/' + domain + '/schema'
    * def v1Forwards = karate.callSingle('classpath:iomete/tests/sql/schema-parity/setup/v1-forwarding.feature', {}).forwarding
    * def v2 = 'api/v2/domains/' + domain + '/sql/schema'
    * def v2Admin = 'api/v2/admin/sql/schema'
    # V2 caches its listings; this run's objects are new
    * def fresh = { forceRefresh: true }
    * def runQuery = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: statement }).result }
    # the platform's error body: V1 wraps with an empty errorCode, V2 names it
    * def errorBody = { errorMessage: '#string', errorCode: '#string', status: '#number' }
    # listings compared as sets of `namespace.name`, since V1 and V2 order them differently
    * def tableKeys = function(rows){ return rows.map(t => t.namespace + '.' + t.name + (t.isView ? ' (view)' : '')).sort() }
    # the deprecated V1 routes see the `default` domain's catalogs, this run's domain may have more
    * def inCatalog = function(rows){ return rows.filter(r => r.catalog == catalogName) }
    # a table's DESCRIBE details as V2 answers them: V2 leaves out the Statistics row on purpose
    * def detailsLikeV2 = function(details){ var copy = {}; for (var key in details) { if (key != 'Statistics') copy[key] = details[key] } return copy }
    # Whether the shared schema server carries the arrow-server fixes the table-details checks
    # compare (DESCRIBE details, Spark types, views, the namespace refresh). The platform version
    # can't tell: a main build or a 4.0.2 install can still run an older schema server image. An
    # older arrow-server sends no metadata columns, so V2 answers `null` for them on an Iceberg
    # table; a server with the fixes sends Iceberg's `_spec_id`, `_file`, ...
    * configure retry = { count: 10, interval: 3000 }
    # The run's database is new: list the catalog's namespaces first. That refreshes the server's
    # namespace list on every server, while an older one doesn't refresh it on a table lookup
    # and would answer 404 for the table until its cache expires
    Given url baseUrl
    And path v2, 'catalogs', catalogName, 'namespaces'
    And params fresh
    And retry until responseStatus == 200 && response.map(n => n.namespace).includes(namespace)
    When method get
    Then status 200
    Given path v2, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    * def schemaServerFixed = response.metadataColumns != null
    # A skip would also hide the regression these checks guard (V2 losing its metadata columns
    # again), so a target known to run the fixed image sets IOMETE_REQUIRE_SCHEMA_SERVER_FIXES=true
    # and fails instead. Turn it on in CI once the e2e peer's default schema server image has them.
    * def requireFixes = java.lang.System.getenv('IOMETE_REQUIRE_SCHEMA_SERVER_FIXES') == 'true'
    * if (!schemaServerFixed && requireFixes) karate.fail('IOMETE_REQUIRE_SCHEMA_SERVER_FIXES is set, but V2 returns no metadata columns: the schema server lacks the arrow-server fixes, or they regressed')
    * if (!schemaServerFixed) karate.log('the schema server predates the arrow-server fixes (no metadata columns on V2), the checks that need them skip')
