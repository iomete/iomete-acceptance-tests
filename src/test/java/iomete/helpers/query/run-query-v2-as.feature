@ignore
Feature: Run a V2 query AS a specific user (by access token); optionally retry until a predicate.
  Unlike run-query-v2.feature (which runs as the admin IOMETE_TOKEN and fails on any non-
  COMPLETED result), this acts as the given user and RETURNS the terminal state so callers can
  assert on deny/failure. Call it with:
    karate.call('classpath:iomete/helpers/query/run-query-v2-as.feature',
                { userToken: t, computeName: c, statement: s })
  Optionally retry: Ranger pushes new policies to Spark on a delay (~10s) and a submitted
  query reaches a terminal state that never changes, so each retry SUBMITS A FRESH query
  (Karate's `retry until` replays one request and can't resubmit). Pass a predicate over the
  result plus how many attempts:
    karate.call('classpath:iomete/helpers/query/run-query-v2-as.feature',
                { userToken: t, computeName: c, statement: s,
                  predicate: function(r){ return r.status == 'FAILED' }, attempts: 15 })
  Optional: attempts (default 1 = no retry), intervalMs (default 3000). Returns:
    submitStatus   HTTP status of the submit (200 when accepted)
    status         terminal query status (COMPLETED / FAILED / CANCELLED)
    queryResponse  the final GET response (includes error text on FAILED)
    resultData     the /result response (columns, values, dataCount) when COMPLETED; else null

  Scenario: submit as the user, poll to terminal, and resubmit until the predicate holds
    * def attempts = karate.get('attempts', 1)
    * def intervalMs = karate.get('intervalMs', 3000)
    * def predicate = karate.get('predicate', function(r){ return true })
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'

    # replace the global admin headers so the request runs as this user only
    # (mirror how IOMETE_TOKEN is sent: both X-API-Token and Authorization Bearer)
    * configure headers = { 'X-API-Token': '#(userToken)', Authorization: '#("Bearer " + userToken)' }

    Given url baseUrl
    And path queriesPath
    And request { statement: '#(statement)', clusterName: '#(computeName)' }
    When method post
    * def submitStatus = responseStatus
    * def submitBody = response
    * if (responseStatus != 200) karate.abort()

    * def queryId = response.queryId
    # polled often, since most statements finish in well under a second; same 60s budget
    * configure retry = { count: 120, interval: 500 }
    Given url baseUrl
    And path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED', 'CANCELLED'].includes(response.status)
    When method get
    Then status 200
    * def status = response.status
    * def queryResponse = response

    # fetch the row data when the query completed (null otherwise, e.g. on a deny/FAILED)
    Given url baseUrl
    And path queriesPath, queryId, 'result'
    When method get
    * def resultData = responseStatus == 200 ? response : null

    # retry-until: if the predicate isn't satisfied and attempts remain, resubmit a fresh query
    * def satisfied = predicate({ submitStatus: submitStatus, status: status, queryResponse: queryResponse, resultData: resultData })
    * if (!satisfied && attempts > 1) karate.log('predicate not met (status=' + status + '), ' + (attempts - 1) + ' attempt(s) left')
    * eval if (!satisfied && attempts > 1) java.lang.Thread.sleep(intervalMs)
    * def retryArgs = { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(statement)', predicate: '#(predicate)', attempts: '#(attempts - 1)', intervalMs: '#(intervalMs)' }
    * def next = (!satisfied && attempts > 1) ? karate.call('classpath:iomete/helpers/query/run-query-v2-as.feature', retryArgs) : null
    * def submitStatus = next ? next.submitStatus : submitStatus
    * def status = next ? next.status : status
    * def queryResponse = next ? next.queryResponse : queryResponse
    * def resultData = next ? next.resultData : resultData
