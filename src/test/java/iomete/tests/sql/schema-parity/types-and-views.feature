@lock=sql
Feature: SQL schema parity — column types, comments, partitions and views match V1

  V2 table details must describe a table the way V1 did: the same type names, nested types,
  column and table comments and partition transforms, and a view that `spark_catalog` lists but
  whose catalog cannot load it as a view (a Hive view), which V2 used to answer 404 for. The
  scenario owns a database with one Iceberg table covering those and a view over it, created
  through the shared SQL compute and dropped afterwards. V1 here is the deprecated native routes
  (see setup/parity.feature). A second scenario does the same for a parquet table with char(n)
  and varchar(n) columns, which V2 used to answer as string. A third scenario checks that a table property that looks like a
  secret is never returned in plain text.

  Skips when ARROW_FLIGHT_FOR_DB_EXPLORER is off: every V2 schema endpoint answers 409 then.

  Background:
    * url baseUrl
    * if (!arrowFlightDbExplorerEnabled) karate.log('ARROW_FLIGHT_FOR_DB_EXPLORER is off, V2 schema routes are not served here, skipping')
    * if (!arrowFlightDbExplorerEnabled) karate.abort()
    # the V2 fixes these checks compare ship in 4.0.2
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the V2 schema fixes these checks compare, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()
    # route prefixes, the seeded catalog and the comparison helpers
    * def ctx = karate.call('classpath:iomete/tests/sql/schema-parity/setup/parity.feature', { domain: domain })
    * def v1Native = ctx.v1Native
    * def v2 = ctx.v2
    * def catalogName = ctx.catalogName
    * def fresh = ctx.fresh
    * def runQuery = ctx.runQuery
    * def detailsLikeV2 = ctx.detailsLikeV2
    * def schemaServerFixed = ctx.schemaServerFixed
    * def namespace = ctx.namespace

  Scenario: a typed, commented, partitioned table and a view over it are described the same on V1 and V2
    # DESCRIBE details, Spark types and Hive views come from the schema server's arrow-server
    * if (!schemaServerFixed) karate.abort()

    # ===== Setup: a database of this scenario's own, the table and a view =====
    * def db = 'karate_parity_types_' + runId
    * def full = catalogName + '.' + db
    # DROP DATABASE ... CASCADE leaves the tables behind in this catalog (setup/ddl-db.feature),
    # so the view and the table go first
    * configure afterScenario = function(){ runQuery('DROP VIEW IF EXISTS ' + full + '.typed_view'); runQuery('DROP TABLE IF EXISTS ' + full + '.typed'); runQuery('DROP DATABASE IF EXISTS ' + full) }
    * runQuery('CREATE DATABASE IF NOT EXISTS ' + full)
    * runQuery("CREATE TABLE IF NOT EXISTS " + full + ".typed (id BIGINT COMMENT 'order id', qty INT, price DECIMAL(10,2), ratio FLOAT, score DOUBLE, flag BOOLEAN, note STRING, payload BINARY, day DATE, created_at TIMESTAMP, created_ntz TIMESTAMP_NTZ, tags ARRAY<STRING>, attrs MAP<STRING, INT>, address STRUCT<city: STRING COMMENT 'city name', zip: INT>) COMMENT 'typed table' PARTITIONED BY (days(created_at), bucket(4, id))")
    * runQuery('CREATE OR REPLACE VIEW ' + full + '.typed_view AS SELECT id, qty, address FROM ' + full + '.typed')
    # the shared schema server can take a few seconds to see objects the compute just created,
    # even with forceRefresh, so the V2 reads below wait for them
    * configure retry = { count: 10, interval: 3000 }

    # ===== 1. The table: types, comments and partitions match V1 =====

    # V1 (native): describe the typed table
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables', 'typed'
    When method get
    Then status 200
    * def v1Table = response
    # the comments are there to compare, not just absent on both sides
    And match v1Table.columns contains { name: 'id', dataType: 'bigint', comment: 'order id' }

    # V2: describe the typed table
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables', 'typed'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    # type names, nesting and comments (`columns[].comment`, `fields[].metadata.comment`)
    And match response.columns == v1Table.columns
    And match response.fields == v1Table.fields
    And match response.partitions == v1Table.partitions
    And match response.isPartitioned == v1Table.isPartitioned
    # the table comment, which V1 lists as `Comment` and keeps out of `Table Properties`
    And match v1Table.detailedTableInfo.Comment == 'typed table'
    And match response.detailedTableInfo.Comment == v1Table.detailedTableInfo.Comment
    # what V1 read from DESCRIBE: the table type and Iceberg's metadata columns
    And match response.type == v1Table.type
    And match response.metadataColumns == v1Table.metadataColumns
    And match response.columnDefaultValues == v1Table.columnDefaultValues
    # every other DESCRIBE row too (Owner, Created Time, Location, Provider, Table Properties…)
    And match detailsLikeV2(response.detailedTableInfo) == detailsLikeV2(v1Table.detailedTableInfo)

    # ===== 2. The view: V2 describes it like V1 (was 404) =====

    # V1 (native): describe the view
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables', 'typed_view'
    When method get
    Then status 200
    * def v1View = response

    # V2: describe the view
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables', 'typed_view'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match response.name == v1View.name
    And match response.columns == v1View.columns
    And match response.fields == v1View.fields
    # the view's details, its SQL included
    And match response.type == v1View.type
    And match v1View.detailedTableInfo['View Text'] == '#string'
    And match response.detailedTableInfo['View Text'] == v1View.detailedTableInfo['View Text']
    # and the other view rows (View Original Text, View Catalog and Namespace, View Query Output Columns…)
    And match detailsLikeV2(response.detailedTableInfo) == detailsLikeV2(v1View.detailedTableInfo)

  Scenario: a parquet table with char and varchar columns is described the same on V1 and V2
    # char(n) and varchar(n) come from the schema server's arrow-server
    * if (!schemaServerFixed) karate.abort()

    # ===== Setup: a non-Iceberg table of this scenario's own =====
    # V2 used to answer `string` for char(n) and varchar(n), and to list only a few DESCRIBE rows
    # for a table that is not Iceberg
    * def db = 'karate_parity_chars_' + runId
    * def full = catalogName + '.' + db
    * configure afterScenario = function(){ runQuery('DROP TABLE IF EXISTS ' + full + '.chars'); runQuery('DROP DATABASE IF EXISTS ' + full) }
    * runQuery('CREATE DATABASE IF NOT EXISTS ' + full)
    * runQuery('CREATE TABLE IF NOT EXISTS ' + full + '.chars (id INT, code CHAR(3), label VARCHAR(10)) USING parquet')
    * configure retry = { count: 10, interval: 3000 }

    # V1 (native): describe the table
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables', 'chars'
    When method get
    Then status 200
    * def v1Table = response
    # the lengths are there to compare, not just `string` on both sides
    And match v1Table.columns contains { name: 'code', dataType: 'char(3)', comment: '##string' }

    # V2: describe the table
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables', 'chars'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match response.columns == v1Table.columns
    And match response.fields == v1Table.fields
    And match response.type == v1Table.type
    And match detailsLikeV2(response.detailedTableInfo) == detailsLikeV2(v1Table.detailedTableInfo)

  Scenario: a table property that looks like a secret is redacted on V1 and V2

    # ===== Setup: a table of this scenario's own with a secret-looking and a plain property =====
    # In the run's seeded database rather than a new one: redaction is iom-sql's, and a schema
    # server without the namespace refresh fix can't see a database created a moment ago
    * def db = namespace
    * def full = catalogName + '.' + db
    * def secretValue = 'karate-secret-' + runId
    * configure afterScenario = function(){ runQuery('DROP TABLE IF EXISTS ' + full + '.parity_props') }
    * runQuery("CREATE TABLE IF NOT EXISTS " + full + ".parity_props (id INT) TBLPROPERTIES ('karate.secret.key' = '" + secretValue + "', 'karate.note' = 'visible')")
    * configure retry = { count: 10, interval: 3000 }

    # V1 (native): describe the table
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables', 'parity_props'
    When method get
    Then status 200
    And match JSON.stringify(response).includes(secretValue) == false

    # V2: describe the table
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables', 'parity_props'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match JSON.stringify(response).includes(secretValue) == false
    # the property is listed with its value redacted, a plain one as it is
    And match response.detailedTableInfo['Table Properties'] contains 'karate.secret.key=*********(redacted)'
    And match response.detailedTableInfo['Table Properties'] contains 'karate.note=visible'
