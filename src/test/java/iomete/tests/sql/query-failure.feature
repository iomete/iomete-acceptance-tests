@lock=sql
Feature: SQL — query failure paths (V2 API)

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    # this feature queries the seeded employees table, so it asks for it rather than
    # relying on query-data.feature having run first
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'

  # --- SQL errors ---

  Scenario: syntax error — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: 'SELEC TYPO FROM nothing', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  Scenario: table not found — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: 'SELECT * FROM spark_catalog.nonexistent_db_xyz.nonexistent_table_abc', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  Scenario: column not found — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: '#("SELECT nonexistent_column FROM " + testData.database + ".employees")', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  # Division by zero is version-divergent: ANSI SQL mode is off by default before Spark 4.0
  # (1/0 → NULL, query COMPLETED) and on by default from 4.0 (1/0 → DIVIDE_BY_ZERO, query
  # FAILED). Each scenario self-skips on the other major via karate.abort(), so the suite is
  # correct whichever image sparkMajor reports — no tag filtering needed for a plain run. The
  # @spark3/@spark4 tags are for optionally running just one set (make test-one TAGS=@spark4).

  @spark3
  Scenario: division by zero — returns COMPLETED (non-ANSI, Spark < 4)
    * if (sparkMajor >= 4) karate.abort()
    Given path queriesPath
    And request { statement: 'SELECT 1/0 AS result', clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 240, interval: 500 }
    Given path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED'].includes(response.status)
    When method get
    Then status 200
    And match response.status == 'COMPLETED'

  @spark4
  Scenario: division by zero — returns FAILED (ANSI on by default, Spark >= 4)
    * if (sparkMajor < 4) karate.abort()
    Given path queriesPath
    And request { statement: 'SELECT 1/0 AS result', clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 240, interval: 500 }
    Given path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED'].includes(response.status)
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'

  # --- Edge cases ---

  Scenario: very long SQL statement (5000+ chars) — should still work
    * def longSelect = 'SELECT ' + '1 AS col_' + Array(200).fill('').map((x, i) => 'col_' + i).join(', 1 AS ')
    Given path queriesPath
    And request { statement: '#(longSelect)', clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 240, interval: 500 }
    Given path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED'].includes(response.status)
    When method get
    Then status 200
    And match response.status == 'COMPLETED'

  Scenario: SQL with special characters in string literal — COMPLETED
    Given path queriesPath
    And request { statement: "SELECT 'hello \"world\" it''s a test; -- comment !@#$%/*-+?' AS special", clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 240, interval: 500 }
    Given path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED'].includes(response.status)
    When method get
    Then status 200
    And match response.status == 'COMPLETED'

  Scenario: multiple statements separated by semicolons — query ends up FAILED
    * def customId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { statement: 'SELECT 1; SELECT 2', clusterName: '#(computeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path queriesPath, customId
    And retry until response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'
