@ignore
Feature: Ask iom-sql V2 once to cancel a query, then read its status (plumbing for cancel-query-v2.feature).
  The DELETE's own answer is not trusted: iom-sql answers 400 for a query that is still PENDING
  as well as for one that has finished, so the status read after it is what the caller acts on.
  Returns status, null when iom-sql does not know the query (404), or UNKNOWN when the status
  could not be read (any other HTTP status), so the caller tries again.

  Scenario: cancel once and read the status
    * def queryPath = '/api/v2/domains/' + domain + '/sql/queries'
    Given url baseUrl
    And path queryPath, queryId
    When method delete

    Given url baseUrl
    And path queryPath, queryId
    When method get
    * def status = responseStatus == 200 ? response.status : responseStatus == 404 ? null : 'UNKNOWN'
    * if (responseStatus != 200 && responseStatus != 404) karate.log('could not read the status of query', queryId, '- HTTP', responseStatus)
