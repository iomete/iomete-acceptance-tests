@lock=sql
Feature: SQL — DDL operations (V2 API)

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }
    # resets this run's ddl database once per run (empties it, table by table), before any scenario
    * def ddlDb = karate.callSingle('classpath:iomete/tests/sql/setup/ddl-db.feature', { domain: domain })
    * def db = ddlDb.database

  # --- CREATE TABLE ---

  Scenario: CREATE TABLE — returns COMPLETED with empty result
    * def tableName = db + '.create_test'
    * def result = runQuery('CREATE TABLE ' + tableName + ' (id INT, name STRING)')
    * match result.status == 'COMPLETED'
    * match result.columns == '#[0]'

  Scenario: CREATE TABLE that already exists — query ends up FAILED
    * def tableName = db + '.duplicate_table'
    * runQuery('CREATE TABLE ' + tableName + ' (id INT)')

    # try again — Spark accepts at planning, fails during execution
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: '#("CREATE TABLE " + tableName + " (id INT)")', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'

  Scenario: CREATE OR REPLACE TABLE — always succeeds
    * def tableName = db + '.replace_test'
    * runQuery('CREATE TABLE ' + tableName + ' (id INT)')
    * def result = runQuery('CREATE OR REPLACE TABLE ' + tableName + ' (id INT, name STRING)')
    * match result.status == 'COMPLETED'

  # --- ALTER TABLE ---

  Scenario: ALTER TABLE ADD COLUMN — returns COMPLETED
    * def tableName = db + '.alter_test'
    * runQuery('CREATE TABLE ' + tableName + ' (id INT)')
    * def result = runQuery('ALTER TABLE ' + tableName + ' ADD COLUMN name STRING')
    * match result.status == 'COMPLETED'

  Scenario: ALTER non-existent table — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: 'ALTER TABLE spark_catalog.nonexistent_db_xyz.no_table ADD COLUMN x INT', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  # --- DROP TABLE ---

  Scenario: DROP TABLE — returns COMPLETED
    * def tableName = db + '.drop_test'
    * runQuery('CREATE TABLE ' + tableName + ' (id INT)')
    * def result = runQuery('DROP TABLE ' + tableName)
    * match result.status == 'COMPLETED'

  Scenario: DROP non-existent table — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: 'DROP TABLE spark_catalog.nonexistent_db_xyz.no_table_abc', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'

  Scenario: DROP TABLE IF EXISTS on non-existent — returns COMPLETED (no error)
    * def result = runQuery('DROP TABLE IF EXISTS ' + db + '.surely_does_not_exist_xyz')
    * match result.status == 'COMPLETED'

  # --- DESCRIBE / SHOW ---

  Scenario: DESCRIBE TABLE — returns column metadata as rows
    * def tableName = db + '.describe_test'
    * runQuery('CREATE TABLE ' + tableName + ' (id INT, name STRING, salary DOUBLE)')
    * def result = runQuery('DESCRIBE TABLE ' + tableName)
    * match result.status == 'COMPLETED'
    * match result.columns[0].field == 'col_name'
    * match result.values contains 'id'
    * match result.values contains 'name'
    * match result.values contains 'salary'

  Scenario: SHOW TABLES — returns table list
    * def result = runQuery('SHOW TABLES IN ' + db)
    * match result.status == 'COMPLETED'
    * match result.columns[*].field contains 'tableName'

  Scenario: SHOW CREATE TABLE — returns DDL statement
    * def tableName = db + '.show_create_test'
    * runQuery('CREATE TABLE ' + tableName + ' (id INT, name STRING)')
    * def result = runQuery('SHOW CREATE TABLE ' + tableName)
    * match result.status == 'COMPLETED'
    * match result.values[0] contains 'CREATE TABLE'

  # --- CREATE TABLE AS SELECT (CTAS) ---

  Scenario: CREATE TABLE AS SELECT — creates table with data
    * def srcTable = db + '.ctas_src'
    * def dstTable = db + '.ctas_dst'
    * runQuery('CREATE TABLE ' + srcTable + ' (id INT, val STRING)')
    * runQuery("INSERT INTO " + srcTable + " VALUES (1, 'a'), (2, 'b'), (3, 'c')")
    * def result = runQuery('CREATE TABLE ' + dstTable + ' AS SELECT * FROM ' + srcTable)
    * match result.status == 'COMPLETED'

    # verify data
    * def verify = runQuery('SELECT COUNT(*) AS cnt FROM ' + dstTable)
    * match verify.values == [3]
