@lock=sql
Feature: SQL — monitoring details and performance metrics (V2 API)

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    # this feature queries the seeded employees table, so it asks for it rather than
    # relying on query-data.feature having run first
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    * def monitoringPath = '/api/v2/domains/' + domain + '/sql/monitoring/queries'

  # ==========================================================================
  # Monitoring happy path — metadata + performance metrics
  # ==========================================================================

  Scenario: monitoring returns complete metadata and performance metrics for completed query
    Given path queriesPath
    And request { statement: '#("SELECT * FROM " + testData.database + ".employees")', clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 240, interval: 500 }
    Given path queriesPath, queryId
    And retry until response.status == 'COMPLETED'
    When method get
    Then status 200

    * configure retry = { count: 5, interval: 2000 }
    Given path monitoringPath, queryId
    And retry until responseStatus == 200
    When method get
    Then status 200
    # Core fields
    And match response.queryId == queryId
    And match response.status == 'COMPLETED'
    And match response.domain == domain
    And match response.computeCluster == computeName
    And match response.userId == '#notnull'
    And match response.namespace == '#notnull'
    And match response.source == 'INTERNAL'
    # Timing
    And match response.duration == '#number'
    And assert response.duration > 0
    And match response.startTime == '#number'
    And match response.endTime == '#number'
    And assert response.endTime >= response.startTime
    # Execution
    And match response.sessionId == '#notnull'
    And match response.executionId == '#notnull'
    And match response.totalExecutorTime == '#number'
    And match response.totalMemoryBytes == '#number'
    # Performance metrics
    And match response.performanceMetrics == '#notnull'
    And match response.performanceMetrics.totalTasksCompleted == '#number'
    And match response.performanceMetrics.totalCpuTime == '#number'
    And match response.performanceMetrics.shuffleMetrics == '#notnull'

  # ==========================================================================
  # Cancel
  # ==========================================================================

  Scenario: monitoring response for CANCELLED query has cancelledBy
    Given path queriesPath
    And request { statement: "SELECT java_method('java.lang.Thread','sleep',cast(20000 as long))", clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 15, interval: 1000 }
    Given path queriesPath, queryId
    And retry until response.status != 'PENDING'
    When method get

    Given path queriesPath, queryId
    When method delete
    Then status 200

    * configure retry = { count: 5, interval: 2000 }
    Given path monitoringPath, queryId
    And retry until response.status == 'CANCELLED'
    When method get
    Then status 200
    And match response.status == 'CANCELLED'
    And match response.cancelledBy == '#notnull'

  Scenario: cancel query via monitoring endpoint
    Given path queriesPath
    And request { statement: "SELECT java_method('java.lang.Thread','sleep',cast(20000 as long))", clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 15, interval: 1000 }
    Given path queriesPath, queryId
    And retry until response.status != 'PENDING'
    When method get

    # wait for monitoring to have it
    * configure retry = { count: 5, interval: 2000 }
    Given path monitoringPath, queryId
    And retry until responseStatus == 200
    When method get
    Then status 200

    # cancel via V2 monitoring endpoint (POST, not PUT)
    Given path monitoringPath, queryId, 'cancel'
    When method post
    Then status 204

    # verify cancelled — on Spark 4 a cancelled query keeps its task running, so this one can
    # still be queued behind an earlier scenario's sleep and take a while to report CANCELLED
    * configure retry = { count: 10, interval: 2000 }
    Given path monitoringPath, queryId
    And retry until response.status == 'CANCELLED'
    When method get
    Then status 200
    And match response.status == 'CANCELLED'

  # ==========================================================================
  # Duration computation
  # ==========================================================================

  Scenario: active query has on-the-fly duration > 0
    # The sleep must outlast the status wait below plus the duration read after it, so the
    # query is still genuinely running when monitoring is read — that is the scenario's point.
    Given path queriesPath
    And request { statement: "SELECT java_method('java.lang.Thread','sleep',cast(60000 as long))", clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    # wait until RUNNING — status propagation jitters by double-digit seconds on a busy or
    # remote-plane target, so the budget sits well above that, and well below the sleep
    * configure retry = { count: 15, interval: 3000 }
    Given path queriesPath, queryId
    And retry until response.status != 'PENDING' && response.status != 'SUBMITTED'
    When method get
    Then status 200

    # check monitoring — duration should be computed on-the-fly, not 0
    * configure retry = { count: 5, interval: 2000 }
    Given path monitoringPath, queryId
    And retry until responseStatus == 200 && response.duration > 0
    When method get
    Then status 200
    And assert response.duration > 0

    # cleanup
    Given path queriesPath, queryId
    When method delete
