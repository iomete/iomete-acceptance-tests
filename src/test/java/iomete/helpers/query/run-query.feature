@ignore
Feature: Run a SQL statement and wait until it completes (plumbing, V1 API).
  Generic building block for setup/teardown work — call it with:
    karate.call('classpath:iomete/helpers/query/run-query.feature',
                { statement: 'CREATE TABLE ...', computeName: 'karate-tests' })
  Fails the caller if the statement does not COMPLETE.

  Scenario: submit the statement and poll to completion
    * def queryId = java.util.UUID.randomUUID() + ''
    * def queriesPath = '/api/v1/domains/' + domain + '/sql/queries'
    # readiness probes pass a small retryCount — see run-query-v2.feature, which also explains
    # why retryCount counts 3s of budget while the status is polled every 500ms
    * def retryCount = karate.get('retryCount', 40)
    * def retryConfig = { count: '#(retryCount * 6)', interval: 500 }

    Given url baseUrl
    And path queriesPath
    And request { queryId: '#(queryId)', statement: '#(statement)', clusterName: '#(computeName)', namespace: 'spark_catalog.default' }
    When method post
    Then status 200

    * configure retry = retryConfig
    Given url baseUrl
    And path queriesPath, queryId
    And retry until ['COMPLETED', 'FAILED', 'CANCELLED'].includes(response.status)
    When method get
    Then status 200
    # fail with the platform's own reason (e.g. "Compute ... is not ready"), which a bare match hides
    * if (response.status != 'COMPLETED') karate.fail('query ' + queryId + ' ended ' + response.status + ': ' + (response.errorMessage || response.message || 'no message'))