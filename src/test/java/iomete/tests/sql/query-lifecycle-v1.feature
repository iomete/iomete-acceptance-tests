@lock=sql
Feature: SQL - query lifecycle (V1 API)

  Happy-path E2E test over the V1 API: submit, poll until completed, read the stored result.
  V1 reaches a compute by its in-cluster address, so this skips when the run's SQL compute is on a remote data plane.
  There is no cleanup: V1 has no delete-query endpoint (DELETE only cancels). Each scenario submits under a fresh
  queryId, so a feature retry never meets the query of the attempt before it.

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * if (isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('skipping: compute ' + sqlCompute.computeName + ' is on remote data plane ' + sqlCompute.computeDataPlane); karate.abort() }
    * def computeName = sqlCompute.computeName
    * def queriesPath = '/api/v1/domains/' + domain + '/sql/queries'

  Scenario: submit a query, poll until completed, read the stored result
    * def queryId = java.util.UUID.randomUUID().toString()
    Given path queriesPath
    And request { queryId: '#(queryId)', statement: 'SELECT 1 AS one', clusterName: '#(computeName)' }
    When method post
    Then status 200

    * configure retry = { count: 240, interval: 500 }
    Given path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED', 'CANCELLED'].includes(response.status)
    When method get
    Then status 200
    And match response.status == 'COMPLETED'

    # V1 rows are objects with string values. The column type name differs by transport (thrift or arrow_flight,
    # set by iom-sql's SQL_COMPUTE_DRIVER env var), so the type is matched as any string
    Given path queriesPath, queryId, 'result'
    When method get
    Then status 200
    And match response.status == 'COMPLETED'
    And match response.rows == [{ one: '1' }]
    And match response.dataCount == 1
    And match response.columns == [{ field: 'one', type: '#string' }]

  Scenario: read a result window that crosses the 1000-row chunk boundary
    # builds from main count as newer
    * if (!platformAtLeast('4.0.2')) { karate.log('result windows ship in 4.0.2: skipping on ' + platformVersion); karate.abort() }

    # the LIMIT stores every row, since the submit default limit is 100; ORDER BY fixes the id order
    * def total = 1500
    * def statement = 'SELECT id FROM range(' + total + ') ORDER BY id LIMIT ' + total
    * def queryId = karate.call('classpath:iomete/helpers/query/run-query.feature', { statement: statement, computeName: computeName }).queryId

    * def offset = 900
    * def limit = 200
    * def expectedWindow = []
    * eval for (var n = offset; n < offset + limit; n++) expectedWindow.push({ id: '' + n })
    Given path queriesPath, queryId, 'result'
    And param offset = offset
    And param limit = limit
    When method get
    Then status 200
    And match response.status == 'COMPLETED'
    And match response.dataCount == total
    And match response.rows == expectedWindow
    And match response.columns == [{ field: 'id', type: '#string' }]
