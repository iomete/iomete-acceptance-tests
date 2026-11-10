@ignore
Feature: Run a SQL statement via the V2 API and return its result (plumbing).
  Building block for tests that assert on query results — call it with:
    def outcome = karate.call('classpath:iomete/helpers/query/run-query-v2.feature',
                              { statement: 'SELECT ...', computeName: 'karate-tests' })
  and read outcome.result (the /result response: columns, values, dataCount).

  Scenario: submit, poll to completion, fetch the result
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    # readiness probes pass a small retryCount: an attempt against a hanging compute must
    # fail fast, not hold its caller for the full budget of a real query
    * def retryCount = karate.get('retryCount', 40)
    # retryCount counts 3s of budget (40 = 2 min), but the status is polled every 500ms: most
    # statements finish in well under a second, and a 3s interval made each one cost 3s (a
    # teardown's ~40 DROPs alone took two minutes)
    * def retryConfig = { count: '#(retryCount * 6)', interval: 500 }
    * configure retry = retryConfig

    Given url baseUrl
    And path queriesPath
    And request { statement: '#(statement)', clusterName: '#(computeName)' }
    When method post
    Then status 200
    * def queryId = response.queryId

    Given url baseUrl
    And path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED', 'CANCELLED'].includes(response.status)
    When method get
    Then status 200
    # fail with the platform's own reason (e.g. "Compute ... is not ready"), which a bare match hides
    * if (response.status != 'COMPLETED') karate.fail('query ' + queryId + ' ended ' + response.status + ': ' + (response.errorMessage || response.message || 'no message'))

    Given url baseUrl
    And path queriesPath, queryId, 'result'
    When method get
    Then status 200
    * def result = response