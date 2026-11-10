@lock=sql
Feature: SQL — the Spark plan graph and the admin cancel (V2 monitoring API)

  The console's Query Monitoring page opens a query with its Spark plan, and the admin's copy of
  the page can cancel a running query in any domain. Both are checked against a query that
  really ran on the shared compute: the plan graph is what the compute's listener sent with its
  query events, and an admin cancel ends a running one.

  Background:
    * url baseUrl
    # seeds this run's database from setup/data/ fixtures, once per run
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def computeName = testData.computeName
    * def database = testData.database
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    * def monitoringPath = '/api/v2/domains/' + domain + '/sql/monitoring/queries'
    * def adminMonitoringPath = '/api/v2/admin/sql/monitoring/queries'

  Scenario: a completed query's Spark plan graph is readable, for the domain and for the admin
    # a scan of a real table, so Spark builds an execution plan for it
    * def outcome = karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: 'SELECT name FROM ' + database + '.employees ORDER BY name' })
    * def queryId = outcome.queryId

    # the compute's listener sends the graph with its query events (execution start, plan
    # updates, completion) and iom-sql keeps the latest it got, so it can land a little after the
    # status does; until the first one lands the endpoint answers 404
    * configure retry = { count: 10, interval: 3000 }
    Given path monitoringPath, queryId, 'spark-plan-graph'
    And retry until responseStatus == 200
    When method get
    Then status 200
    # stored and served as an opaque string: a real plan graph parses and has nodes
    * def graph = typeof response == 'string' ? karate.fromString(response) : response
    And match graph.nodes == '#[_ > 0]'
    And match graph.edges == '#array'

    Given path adminMonitoringPath, queryId, 'spark-plan-graph'
    When method get
    Then status 200
    * def adminGraph = typeof response == 'string' ? karate.fromString(response) : response
    And match adminGraph.nodes == graph.nodes

  Scenario: an admin cancels a running query through the admin monitoring view
    Given path queriesPath
    And request { statement: "SELECT java_method('java.lang.Thread','sleep',cast(60000 as long))", clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    # a PENDING query cannot be cancelled yet (400), so wait until the compute has it. Status
    # propagation jitters by double-digit seconds, and the shared compute can queue it behind
    # other lanes' queries, hence the budget; the sleep still runs once it starts.
    # The wait also ends on a failure, which would otherwise surface as a confusing 400 below.
    * configure retry = { count: 40, interval: 3000 }
    Given path queriesPath, queryId
    And retry until response.status != 'PENDING' && response.status != 'SUBMITTED'
    When method get
    Then status 200
    And match response.status == 'RUNNING'

    Given path adminMonitoringPath, queryId, 'cancel'
    When method post
    Then status 204

    # the cancel writes CANCELLED in the same call, and the status guard never lets the compute's
    # later COMPLETED overwrite a terminal status, so this is a short poll for the read to catch
    # up, not a wait for the sleep (on Spark 4 the cancelled task holds its executor slot until
    # the sleep ends, which only delays queries queued behind it)
    * configure retry = { count: 10, interval: 2000 }
    Given path adminMonitoringPath, queryId
    And retry until response.status == 'CANCELLED'
    When method get
    Then status 200
    And match response.status == 'CANCELLED'
    And match response.cancelledBy == '#notnull'
