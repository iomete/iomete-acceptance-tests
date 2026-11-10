@lock=sql
Feature: SQL — query cancel (V2 API)

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    * def longQuery = "SELECT java_method('java.lang.Thread','sleep',cast(20000 as long))"

  # --- Cancel active query ---

  Scenario: cancel query while SUBMITTED/RUNNING — returns CANCELLED
    Given path queriesPath
    And request { statement: '#(longQuery)', clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    # wait until past PENDING
    * configure retry = { count: 15, interval: 1000 }
    Given path queriesPath, queryId
    And retry until response.status != 'PENDING'
    When method get
    Then status 200

    # cancel
    Given path queriesPath, queryId
    When method delete
    Then status 200
    And match response.status == 'CANCELLED'

    # verify final state
    Given path queriesPath, queryId
    When method get
    Then status 200
    And match response.status == 'CANCELLED'

  # --- Cancel metadata ---

  Scenario: cancel sets cancelledBy in monitoring
    Given path queriesPath
    And request { statement: '#(longQuery)', clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    * configure retry = { count: 15, interval: 1000 }
    Given path queriesPath, queryId
    And retry until response.status != 'PENDING'
    When method get
    Then status 200

    Given path queriesPath, queryId
    When method delete
    Then status 200

    # verify via monitoring
    * configure retry = { count: 5, interval: 1000 }
    Given path '/api/v2/domains/' + domain + '/sql/monitoring/queries', queryId
    And retry until response.status == 'CANCELLED'
    When method get
    Then status 200
    And match response.cancelledBy == '#notnull'

