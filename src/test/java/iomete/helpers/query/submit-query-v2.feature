@ignore
Feature: Submit a SQL statement via the V2 API and return its id without waiting (plumbing).
  For tests that follow the query some other way (its status, a cancel) — call it with:
    def queryId = karate.call('classpath:iomete/helpers/query/submit-query-v2.feature',
                              { statement: 'SELECT ...', computeName: 'karate-tests', limit: 150 }).queryId
  limit is optional: how many rows iom-sql stores (100 when not sent).
  queryId is optional: iom-sql takes the caller's id, so a teardown can be registered for it
  before the submit, and still find the query when the submit's response is lost.

  Scenario: submit
    Given url baseUrl
    And path '/api/v2/domains/' + domain + '/sql/queries'
    # params leaves out a null value, so no limit is sent when none was given
    And params { limit: '#(karate.get("limit", null))' }
    And request { statement: '#(statement)', clusterName: '#(computeName)', queryId: '##(karate.get("queryId", null))' }
    When method post
    Then status 200
    * def queryId = response.queryId
