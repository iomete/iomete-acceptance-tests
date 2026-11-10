@lock=security
Feature: Data security — a row-filter policy restricts a user's rows (E2E enforcement)

  Proves the row-filter (RLS) policy is enforced by Spark/Ranger, not just stored.
  Arrange (admin): onboard the query-user and restrict customers to region 'AMER' for them.
  Act (user): karate-security-user selects from customers, as itself.
  Assert: admin sees all rows; the user sees only the AMER rows.
  Ranger pulls new policies on a delay (~10s), so the query is retried until the filter applies.

  Background:
    * url baseUrl
    * def ctx = karate.callSingle('classpath:iomete/tests/data-security/setup/security-user.feature', { domain: domain })
    * def user = ctx.user
    * def database = ctx.database
    * def computeName = ctx.computeName
    * def userToken = ctx.userToken

    # expected rows derived from the same fixture the tables are seeded from
    * def customers = read('classpath:iomete/tests/data-security/setup/data/customers.json')
    * def amerCount = customers.filter(c => c.region == 'AMER').length

    # admin restricts customers to region 'AMER' for this user (not the user itself)
    * def filter = call read('classpath:iomete/tests/data-security/setup/policies/filter-region-policy.feature') { user: '#(user)', database: '#(database)' }
    * def policyName = filter.policyName

    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'filter', name: policyName });
      }
      """

  Scenario: karate-security-user sees only AMER rows of customers
    * def statement = "SELECT id FROM " + database + ".customers"

    # admin sees every row
    * def adminRun = call read('classpath:iomete/helpers/query/run-query-v2.feature') { computeName: '#(computeName)', statement: '#(statement)' }
    * match adminRun.result.values.length == customers.length

    # the user sees only AMER rows — retry until the filter takes effect
    * def expectedRows = amerCount
    * def isFiltered = function(r){ return r.status == 'COMPLETED' && r.resultData != null && r.resultData.values.length == expectedRows }
    * def result = call read('classpath:iomete/helpers/query/run-query-v2-as.feature') { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(statement)', predicate: '#(isFiltered)', attempts: 15 }

    * match result.resultData.values.length == amerCount
    * assert amerCount < customers.length
