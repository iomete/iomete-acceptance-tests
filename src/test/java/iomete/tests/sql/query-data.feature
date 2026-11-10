@lock=sql
Feature: SQL — query seeded tables (V2 API)

  Background:
    * url baseUrl
    # seeds this run's database from setup/data/ fixtures, once per run
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def computeName = testData.computeName
    * def database = testData.database
    * def employees = testData.employees
    * def runQuery = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: statement }).result }

  Scenario: count all rows
    * def result = runQuery('SELECT COUNT(*) AS total FROM ' + database + '.employees')
    * match result.values == [ '#(employees.length)' ]

  Scenario: filter and order by
    * def result = runQuery("SELECT name FROM " + database + ".employees WHERE salary > 4000 ORDER BY name")
    * def expected = employees.filter(e => e.salary > 4000).map(e => e.name).sort()
    * match result.values == expected

  Scenario: aggregate
    * def result = runQuery('SELECT MAX(salary) AS top FROM ' + database + '.employees')
    * def expected = Math.max.apply(null, employees.map(e => e.salary))
    * match result.values == [ '#(expected)' ]