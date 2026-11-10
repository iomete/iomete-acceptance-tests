@lock=sql
Feature: Compute runtime, the console's instances and logs views read the live driver

  The platform reads these from the data plane: the driver pod from Kubernetes and its log lines
  from the pod. So the scenario runs a query of its own and looks for it in what comes back,
  which no stored value can answer for.

  It only reads, so it borrows the run's shared SQL compute rather than starting one. The
  driver's events are checked in compute-lifecycle instead: Kubernetes keeps events for about an
  hour, and the shared compute's driver can be older than that by the time this runs.

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeId = sqlCompute.computeId
    * def computeName = sqlCompute.computeName
    * def computePath = 'api/v2/domains/' + domain + '/compute'

  Scenario: the driver pod is listed as running, and its logs carry a query it just ran
    Given path computePath, computeId, 'instances'
    When method get
    Then status 200
    * def driver = response.find(p => p.name.endsWith(computeName + '-driver'))
    * assert driver != null
    * match driver contains { status: 'Running' }

    # The SQL editor's (v1) path logs every statement it hands Spark, so a unique literal in one
    # is a line only this execution's query can have put there. v1 cannot reach a remote plane and
    # the v2 path logs no statement text, so there nothing in the log is this execution's own and
    # the log reads are skipped rather than passed on whatever the driver already wrote.
    * if (isRemotePlane(sqlCompute.computeDataPlane)) karate.log('the shared compute is on a remote plane, where no query leaves its text in the driver log; skipping the log reads')
    * if (isRemotePlane(sqlCompute.computeDataPlane)) karate.abort()
    * def marker = 'karate-log-' + runId + '-' + java.util.UUID.randomUUID()
    * karate.call('classpath:iomete/helpers/query/run-query.feature', { domain: domain, computeName: computeName, statement: "SELECT '" + marker + "' AS marker" })
    * def proves = function(text) { return text.includes(marker) }
    # the line reaches the log a moment after the query completes; downloads are octet streams
    * def logText = function(type, body, bytes) { return type == 'json' ? JSON.stringify(body) : new java.lang.String(bytes, 'UTF-8') + '' }
    * configure retry = { count: 12, interval: 5000 }

    # the console's driver log, the same pod read by its name, and both downloads, which stream
    # the whole log rather than a range
    Given path computePath, computeId, 'logs'
    And param range = '15m'
    And retry until responseStatus == 200 && proves(logText(responseType, response, responseBytes))
    When method get

    Given path computePath, computeId, 'instances', driver.name, 'logs'
    And param range = '15m'
    And retry until responseStatus == 200 && proves(logText(responseType, response, responseBytes))
    When method get

    Given path computePath, computeId, 'logs', 'download'
    And retry until responseStatus == 200 && proves(logText(responseType, response, responseBytes))
    When method get

    Given path computePath, computeId, 'instances', driver.name, 'logs', 'download'
    And retry until responseStatus == 200 && proves(logText(responseType, response, responseBytes))
    When method get
