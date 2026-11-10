@lock=sql
Feature: SQL — query lifecycle (V2 API)

  Happy-path E2E test: submit → poll → fetch result.

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'

  Scenario: submit a query, poll until completed, fetch the result
    Given path queriesPath
    And request { statement: 'SELECT 1 AS one', clusterName: '#(computeName)' }
    When method post
    Then status 200
    And match response.queryId == '#string'
    * def queryId = response.queryId

    # poll status until the query reaches a terminal state
    * configure retry = { count: 360, interval: 500 }
    Given path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED', 'CANCELLED'].includes(response.status)
    When method get
    Then status 200
    And match response.status == 'COMPLETED'
    And match response.statement == 'SELECT 1 AS one'

    # fetch the result
    Given path queriesPath, queryId, 'result'
    When method get
    Then status 200
    And match response.status == 'COMPLETED'
    And match response.columns == [{ field: 'one', type: 'integer' }]
    And match response.values == [1]
