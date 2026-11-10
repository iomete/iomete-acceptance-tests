@ignore
Feature: Trigger one maintenance operation on a table and wait for its run to finish.
  The table must already have the operation enabled, the config cache must have caught up, and
  the catalog must be bound to a compute and a service account (see manual-run.feature).
  The scheduler can start the same operation on a qualifying table first; the trigger then
  answers 409 and this follows that run instead, since either way the operation has to run.
  Call it with { compactionPath, tablePath, catalogName, database, tableName, operationType }.
  Returns run, the finished run's history record (asserted COMPLETED).

  Scenario: trigger the operation, follow its run to the end, read its record
    * url baseUrl

    Given path tablePath + '/trigger/' + operationType
    And request {}
    When method post
    Then assert responseStatus == 200 || responseStatus == 409
    * def triggeredId = responseStatus == 200 ? response.id : null

    Given path compactionPath + '/history'
    And params { catalog: '#(catalogName)', database: '#(database)', table: '#(tableName)', operationType: '#(operationType)' }
    When method get
    Then status 200
    * if (!triggeredId) karate.log('the scheduler had already started ' + operationType + ' on ' + tableName + ', following that run')
    * def executionRunId = triggeredId ? triggeredId : (response.items.length == 1 ? response.items[0].id : null)
    * match executionRunId == '#notnull'

    # the run is a Spark job on the bound compute, so it takes minutes to reach the history
    * configure retry = { count: 60, interval: 10000 }
    Given path compactionPath + '/history'
    And params { catalog: '#(catalogName)', database: '#(database)', table: '#(tableName)' }
    And retry until response.items.filter(r => r.id == executionRunId && ['COMPLETED', 'FAILED', 'SKIPPED'].includes(r.status)).length > 0
    When method get
    Then status 200

    # SKIPPED only comes from an operation the run sees as disabled, which the caller's cache
    # wait rules out, so the run must have completed, whoever started it
    * def run = response.items.find(r => r.id == executionRunId)
    # the history goes with the catalog when cleanup drops it, so this log line is the only
    # record of why a run did not complete
    * if (run.status != 'COMPLETED') karate.log('maintenance run did not complete: ' + karate.pretty(run))
    And match run.status == 'COMPLETED'
    And match run.operationType == operationType
    And match run.errorMessage == '##null'
    And match run.triggeredBy == '#notnull'

    # the run's own record, as the console opens it from the history
    Given path tablePath + '/history/' + executionRunId
    When method get
    Then status 200
    And match response.id == executionRunId
    And match response.status == 'COMPLETED'
