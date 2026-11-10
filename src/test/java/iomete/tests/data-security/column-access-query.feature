@lock=security
Feature: Data security — column-level access: a user is denied one column but can read the rest (E2E)

  Proves access control is enforced at COLUMN granularity by Spark/Ranger, not just at the table
  level (Spark narrows SELECT to the referenced columns and checks each).
  Arrange (admin): onboard the query-user and deny SELECT on customers.ssn for that user.
  Act (user): karate-security-user selects ssn (blocked) and other columns (allowed), as itself.
  Ranger pulls new policies on a delay (~10s), so the denied query is retried until it FAILS.

  Background:
    * url baseUrl
    * def ctx = karate.callSingle('classpath:iomete/tests/data-security/setup/security-user.feature', { domain: domain })
    * def user = ctx.user
    * def database = ctx.database
    * def computeName = ctx.computeName
    * def userToken = ctx.userToken

    # admin denies the ssn column for this user (not the user itself)
    * def col = call read('classpath:iomete/tests/data-security/setup/policies/deny-ssn-column-policy.feature') { user: '#(user)', database: '#(database)' }
    * def policyName = col.policyName

    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'access', name: policyName });
      }
      """

  Scenario: karate-security-user cannot SELECT ssn but can SELECT other columns of the same table

    # denied column — retry until the deny propagates and the query FAILS
    * def deniedStmt = "SELECT ssn FROM " + database + ".customers"
    * def isDenied = function(r){ return r.status == 'FAILED' }
    * def denied = call read('classpath:iomete/helpers/query/run-query-v2-as.feature') { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(deniedStmt)', predicate: '#(isDenied)', attempts: 15 }
    * match denied.status == 'FAILED'
    * match denied.queryResponse.errorMessage contains 'Permission denied'
    * match denied.queryResponse.errorMessage contains 'ssn'

    # other columns of the same table are still readable (policy is active — the deny above proved it)
    * def allowedStmt = "SELECT id, full_name FROM " + database + ".customers"
    * def allowed = call read('classpath:iomete/helpers/query/run-query-v2-as.feature') { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(allowedStmt)' }
    * match allowed.status == 'COMPLETED'
    * assert allowed.resultData.values.length > 0
