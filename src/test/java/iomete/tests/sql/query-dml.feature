@lock=sql
Feature: SQL — DML operations (V2 API)

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }
    # resets this run's dml database once per run (empties it, table by table), before any scenario
    * def dmlDb = karate.callSingle('classpath:iomete/tests/sql/setup/dml-db.feature', { domain: domain })
    * def db = dmlDb.database

  # --- INSERT ---

  Scenario: INSERT INTO — returns COMPLETED
    * def table = db + '.insert_test'
    * runQuery('CREATE TABLE ' + table + ' (id INT, name STRING, score DOUBLE)')
    * def result = runQuery("INSERT INTO " + table + " VALUES (1, 'alice', 95.5), (2, 'bob', 87.3)")
    * match result.status == 'COMPLETED'

    # verify data exists
    * def verify = runQuery('SELECT COUNT(*) AS cnt FROM ' + table)
    * match verify.values == [2]

  Scenario: INSERT into non-existent table — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: "INSERT INTO spark_catalog.nonexistent_db_xyz.no_table VALUES (1, 'x')", clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  Scenario: INSERT with type mismatch — query ends up FAILED
    * def table = db + '.type_mismatch'
    * runQuery('CREATE TABLE ' + table + ' (id INT, name STRING)')
    * def customId = java.util.UUID.randomUUID().toString()

    Given path queriesPath
    And request { statement: '#("INSERT INTO " + table + " VALUES (\'not_an_int\', 123)")', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  # --- UPDATE ---

  Scenario: UPDATE SET — modifies data correctly
    * def table = db + '.update_test'
    * runQuery('CREATE TABLE ' + table + ' (id INT, name STRING, active BOOLEAN)')
    * runQuery("INSERT INTO " + table + " VALUES (1, 'alice', true), (2, 'bob', true)")
    * def result = runQuery("UPDATE " + table + " SET active = false WHERE id = 2")
    * match result.status == 'COMPLETED'

    # verify
    * def verify = runQuery("SELECT active FROM " + table + " WHERE id = 2")
    * match verify.values == [false]

  Scenario: UPDATE with wrong column — query ends up FAILED
    * def table = db + '.update_bad_col'
    * runQuery('CREATE TABLE ' + table + ' (id INT, name STRING)')
    * runQuery("INSERT INTO " + table + " VALUES (1, 'test')")
    * def customId = java.util.UUID.randomUUID().toString()

    Given path queriesPath
    And request { statement: '#("UPDATE " + table + " SET nonexistent_col = 1")', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  # --- DELETE ---

  Scenario: DELETE WHERE — removes matching rows
    * def table = db + '.delete_test'
    * runQuery('CREATE TABLE ' + table + ' (id INT, name STRING)')
    * runQuery("INSERT INTO " + table + " VALUES (1, 'keep'), (2, 'remove'), (3, 'keep')")
    * def result = runQuery("DELETE FROM " + table + " WHERE id = 2")
    * match result.status == 'COMPLETED'

    # verify
    * def verify = runQuery('SELECT COUNT(*) AS cnt FROM ' + table)
    * match verify.values == [2]

  Scenario: DELETE from non-existent table — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: 'DELETE FROM spark_catalog.nonexistent_db_xyz.no_table WHERE id = 1', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  # --- MERGE ---

  Scenario: MERGE INTO — matched and not matched
    * def target = db + '.merge_target'
    * def source = db + '.merge_source'
    * runQuery('CREATE TABLE ' + target + ' (id INT, name STRING, score INT)')
    * runQuery('CREATE TABLE ' + source + ' (id INT, name STRING, score INT)')
    * runQuery("INSERT INTO " + target + " VALUES (1, 'alice', 80), (2, 'bob', 70)")
    * runQuery("INSERT INTO " + source + " VALUES (2, 'bob', 90), (3, 'carol', 85)")

    * def mergeStmt = 'MERGE INTO ' + target + ' t USING ' + source + ' s ON t.id = s.id WHEN MATCHED THEN UPDATE SET score = s.score WHEN NOT MATCHED THEN INSERT *'
    * def result = runQuery(mergeStmt)
    * match result.status == 'COMPLETED'

    # verify: bob updated, carol inserted
    * def verify = runQuery('SELECT id, score FROM ' + target + ' ORDER BY id')
    * match verify.values == [1, 80, 2, 90, 3, 85]
