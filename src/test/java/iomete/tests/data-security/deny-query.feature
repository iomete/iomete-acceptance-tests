@lock=security
Feature: Data security — a denied user is refused SELECT on the salaries table (E2E enforcement)

  Proves the deny access policy is actually enforced by Spark/Ranger, not just stored.
  Arrange (admin): onboard the query-user and create the deny policy on salaries.
  Act (user): karate-security-user runs a real SELECT on the table, as itself.
  Assert: it gets a "Permission denied" error. Ranger pulls new policies on a delay (~10s),
  so the query is retried until the deny takes effect.

  Background:
    * url baseUrl
    # admin arranges: onboarded query-user (+ warm compute + seeded tables) ...
    * def ctx = karate.callSingle('classpath:iomete/tests/data-security/setup/security-user.feature', { domain: domain })
    * def user = ctx.user
    * def database = ctx.database
    * def computeName = ctx.computeName
    * def userToken = ctx.userToken

    # ... and the deny policy on salaries (created by admin, not the user)
    * def deny = call read('classpath:iomete/tests/data-security/setup/policies/deny-salaries-policy.feature') { user: '#(user)', database: '#(database)' }
    * def policyName = deny.policyName

    # teardown: always remove the policy, pass or fail
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'access', name: policyName });
      }
      """

  Scenario: karate-security-user is denied all access to salaries
    * def statement = 'SELECT * FROM ' + database + '.salaries'

    # the user runs the query, retried until the deny propagates (~10s) and it FAILS
    * def isDenied = function(r){ return r.status == 'FAILED' }
    * def result = call read('classpath:iomete/helpers/query/run-query-v2-as.feature') { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(statement)', predicate: '#(isDenied)', attempts: 15 }

    # the query was denied for this user on this table
    * match result.status == 'FAILED'
    * match result.queryResponse.errorMessage contains 'Permission denied'
    * match result.queryResponse.errorMessage contains user
    * match result.queryResponse.errorMessage contains 'salaries'
