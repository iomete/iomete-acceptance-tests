@lock=sql
Feature: SQL schema parity — a database with no Iceberg table lists and describes the same on V1 and V2

  `spark_catalog` keeps Hive tables (parquet and the like) and Iceberg tables side by side, and V1
  lists them with SHOW TABLES, which sees both. An older schema server (Spark 3.5 images) answers
  V2 from the Iceberg side only, so a database holding only Hive tables listed as empty there and
  its tables and views answered 404, while `default` with no Iceberg table failed with
  `Namespace does not exist`. The scenario owns a database with a parquet
  table and a view over it, and no Iceberg table, created through the shared SQL compute and
  dropped afterwards. V1 here is the deprecated native routes (see setup/parity.feature).

  Skips when ARROW_FLIGHT_FOR_DB_EXPLORER is off: every V2 schema endpoint answers 409 then.

  Background:
    * url baseUrl
    * if (!arrowFlightDbExplorerEnabled) karate.log('ARROW_FLIGHT_FOR_DB_EXPLORER is off, V2 schema routes are not served here, skipping')
    * if (!arrowFlightDbExplorerEnabled) karate.abort()
    # route prefixes, the seeded catalog and the comparison helpers
    * def ctx = karate.call('classpath:iomete/tests/sql/schema-parity/setup/parity.feature', { domain: domain })
    * def v1Native = ctx.v1Native
    * def v2 = ctx.v2
    * def catalogName = ctx.catalogName
    * def fresh = ctx.fresh
    * def runQuery = ctx.runQuery
    * def tableKeys = ctx.tableKeys
    * def detailsLikeV2 = ctx.detailsLikeV2
    # A schema server with the arrow-server fixes answers these itself; on an older one iom-sql
    # falls back to SHOW TABLES and DESCRIBE, which ships in 4.0.3 (builds from main count as newer)
    * def answered = ctx.schemaServerFixed || platformAtLeast('4.0.3')
    * if (!answered) karate.log('platform ' + platformVersion + ' on an older schema server predates the Hive fallbacks, skipping')
    * if (!answered) karate.abort()

  Scenario: a database with only a parquet table and a view lists and describes them on V1 and V2

    # ===== Setup: a database of this scenario's own, with no Iceberg table =====
    * def db = 'karate_parity_hive_' + runId
    * def full = catalogName + '.' + db
    # DROP DATABASE ... CASCADE leaves the tables behind in this catalog (setup/ddl-db.feature),
    # so the view and the table go first
    * configure afterScenario = function(){ runQuery('DROP VIEW IF EXISTS ' + full + '.hive_view'); runQuery('DROP TABLE IF EXISTS ' + full + '.hive_orders'); runQuery('DROP DATABASE IF EXISTS ' + full) }
    * runQuery('CREATE DATABASE IF NOT EXISTS ' + full)
    * runQuery('CREATE TABLE IF NOT EXISTS ' + full + '.hive_orders (id INT, amount DOUBLE) USING parquet')
    * runQuery('CREATE OR REPLACE VIEW ' + full + '.hive_view AS SELECT id FROM ' + full + '.hive_orders')
    # the shared schema server can take a few seconds to see objects the compute just created,
    # even with forceRefresh, so the V2 reads below wait for them
    * configure retry = { count: 10, interval: 3000 }
    # The database is new: list the catalog's namespaces first. An older server doesn't refresh its
    # namespace list on a table lookup, so a stale cache would answer [] or 404 below, not the bug
    Given path v2, 'catalogs', catalogName, 'namespaces'
    And params fresh
    And retry until responseStatus == 200 && response.map(n => n.namespace).includes(db)
    When method get
    Then status 200

    # ===== 1. The listing: V2 has the parquet table and the view, as V1 does =====

    # V1 (native): list the database's tables
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables'
    When method get
    Then status 200
    * def expected = tableKeys(response)
    # the two objects are there to compare, not an empty list on both sides
    And match expected == ([db + '.hive_orders', db + '.hive_view (view)']).sort()

    # V2: list the database's tables (an older schema server answered [] here)
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables'
    And params fresh
    And retry until responseStatus == 200 && tableKeys(response).length == expected.length
    When method get
    Then status 200
    And match tableKeys(response) == expected

    # ===== 2. The parquet table: V2 describes it as V1 does (an older schema server answered 404) =====

    # V1 (native): describe the table
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables', 'hive_orders'
    When method get
    Then status 200
    * def v1Table = response

    # V2: describe the table
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables', 'hive_orders'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match response.columns == v1Table.columns
    And match response.fields == v1Table.fields
    And match response.type == v1Table.type
    And match response.provider == 'parquet'
    And match detailsLikeV2(response.detailedTableInfo) == detailsLikeV2(v1Table.detailedTableInfo)

    # ===== 3. The view: V2 describes it as V1 does (an older schema server answered 404) =====

    # V1 (native): describe the view
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables', 'hive_view'
    When method get
    Then status 200
    * def v1View = response
    And match v1View.type == 'VIEW'

    # V2: describe the view
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables', 'hive_view'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match response.type == 'VIEW'
    And match response.columns == v1View.columns
    And match response.fields == v1View.fields
    And match detailsLikeV2(response.detailedTableInfo) == detailsLikeV2(v1View.detailedTableInfo)
