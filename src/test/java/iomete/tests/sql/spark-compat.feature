@lock=sql
Feature: SQL — Spark version backward compatibility (V2 API)

  Verifies V1 and V2 flows work on both old and new Spark images.
  - Old Spark: compute without HTTP event publisher or Arrow Fetch (pre-V2 image)
  - New Spark: compute with HTTP event publisher + Arrow Fetch (V2-compatible image)
  V2 requires new Spark image. V1 works on both.
  Both compute names come from setup/sql-compute.feature (the SQL suite's compute owner).

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def newComputeName = sqlCompute.computeName
    * def oldComputeName = sqlCompute.oldComputeName
    * def v1QueriesPath = '/api/v1/domains/' + domain + '/sql/queries'
    * def v2QueriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    * def v1MonitoringPath = '/api/v1/domains/' + domain + '/sql/monitoring/queries'
    * def v2MonitoringPath = '/api/v2/domains/' + domain + '/sql/monitoring/queries'

  # ==========================================================================
  # G3: New Spark + V1 flow — V1 submit still works
  # ==========================================================================

  Scenario: new Spark + V1 flow — V1 submit works alongside V2
    # v1 cannot reach a compute on a remote data plane (by design), so this only proves
    # something when the run's SQL compute sits on the local one
    * if (isRemotePlane(sqlCompute.computeDataPlane)) karate.abort()
    * def queryId = java.util.UUID.randomUUID().toString()
    Given path v1QueriesPath
    And request { queryId: '#(queryId)', statement: 'SELECT 1 AS g3_test', clusterName: '#(newComputeName)' }
    When method post
    Then status 200
    And match response.status == 'RUNNING'

    * configure retry = { count: 240, interval: 500 }
    Given path v1QueriesPath, queryId
    And retry until response.status == 'COMPLETED'
    When method get
    Then status 200
    And match response.status == 'COMPLETED'

  # ==========================================================================
  # G4: New Spark still writes to query_states (backward compatibility)
  # V1 monitoring reads query_states — new Spark queries should appear there
  # ==========================================================================

  Scenario: V2 query visible in V1 monitoring (new Spark writes to query_states via events)
    Given path v2QueriesPath
    And request { statement: 'SELECT 1 AS g4_test', clusterName: '#(newComputeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 240, interval: 500 }
    Given path v2QueriesPath, queryId
    And retry until response.status == 'COMPLETED'
    When method get
    Then status 200

    # V1 monitoring should also see it
    * configure retry = { count: 5, interval: 2000 }
    Given path v1MonitoringPath, queryId
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match response.status == 'COMPLETED'

  # ==========================================================================
  # G7: HTTP events don't break V1 behavior
  # ==========================================================================

  Scenario: V1 and V2 submit work concurrently on same compute
    # v1 cannot reach a compute on a remote data plane (by design) — see the skip above
    * if (isRemotePlane(sqlCompute.computeDataPlane)) karate.abort()
    # V1 submit
    * def v1Id = java.util.UUID.randomUUID().toString()
    Given path v1QueriesPath
    And request { queryId: '#(v1Id)', statement: 'SELECT 1 AS v1_concurrent', clusterName: '#(newComputeName)' }
    When method post
    Then status 200

    # V2 submit
    Given path v2QueriesPath
    And request { statement: 'SELECT 2 AS v2_concurrent', clusterName: '#(newComputeName)' }
    When method post
    Then status 200
    * def v2Id = response.queryId

    # both should complete
    * configure retry = { count: 240, interval: 500 }
    Given path v1QueriesPath, v1Id
    And retry until response.status == 'COMPLETED'
    When method get
    Then status 200

    * configure retry = { count: 240, interval: 500 }
    Given path v2QueriesPath, v2Id
    And retry until response.status == 'COMPLETED'
    When method get
    Then status 200

  # ==========================================================================
  # V2 query on old compute (no Arrow Flight) — proper error message (COM-620)
  # TODO will adjust response.errorMessage after the task done
  # ==========================================================================

  Scenario: V2 query on old compute — fails with clear error message
    # the pre-V2 compute is only built when the run asks for it, which only the nightly does
    * if (!includeCompat) karate.abort()
    * def customId = java.util.UUID.randomUUID().toString()
    Given path v2QueriesPath
    And request { statement: 'SELECT 1', clusterName: '#(oldComputeName)', queryId: '#(customId)' }
    When method post

    * configure retry = { count: 120, interval: 500 }
    Given path v2QueriesPath, customId
    And retry until ['COMPLETED', 'FAILED'].includes(response.status)
    When method get
    Then status 200
    And match response.status == 'FAILED'
    And match response.errorMessage == '#notnull'