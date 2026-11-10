@lock=sql
Feature: SQL — CSV export (V2 API)

  The SQL editor's "download as CSV" button streams a completed query's stored result back
  through iom-sql. It is checked against a query that really ran on the shared compute: the
  export streams the rows the seeded table holds, in the order the query asked for.

  Background:
    * url baseUrl
    # seeds this run's database from setup/data/ fixtures, once per run
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def computeName = testData.computeName
    * def database = testData.database
    * def employees = testData.employees
    * def queriesPath = '/api/v2/domains/' + domain + '/sql/queries'
    * def run = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: statement }) }

  Scenario: the CSV export streams the header and every row of a completed query
    * def outcome = run('SELECT id, name, salary FROM ' + database + '.employees ORDER BY id')
    * def queryId = outcome.queryId

    Given path queriesPath, queryId, 'result', 'export', 'csv'
    # the endpoint produces text/csv, so an error would not be rendered as JSON without this
    And header Accept = 'text/csv, application/json'
    When method get
    Then status 200
    And match header Content-Type contains 'text/csv'
    And match header Content-Disposition contains queryId

    # text/csv comes back as a string: a UTF-8 BOM (for Excel), then a header line, then one
    # line per row
    * def csv = '' + response
    And match csv.charCodeAt(0) == 0xFEFF
    * def lines = csv.substring(1).trim().split(/\r?\n/)
    And match lines[0] == 'id,name,salary'
    And assert lines.length == employees.length + 1
    * def names = lines.slice(1).map(l => l.split(',')[1])
    And match names == employees.map(e => e.name)
