@lock=security
Feature: Data security — a user sees a masked column value (E2E enforcement)

  Proves the data-mask policy is enforced by Spark/Ranger, not just stored.
  Arrange (admin): onboard the query-user and mask customers.email for that user.
  Act (user): karate-security-user selects email, as itself.
  Assert: admin still reads the real value; the user reads a hashed (masked) value.
  Ranger pulls new policies on a delay (~10s), so the query is retried until the mask applies.

  Background:
    * url baseUrl
    * def ctx = karate.callSingle('classpath:iomete/tests/data-security/setup/security-user.feature', { domain: domain })
    * def user = ctx.user
    * def database = ctx.database
    * def computeName = ctx.computeName
    * def userToken = ctx.userToken

    # admin masks the email column for this user (not the user itself)
    * def mask = call read('classpath:iomete/tests/data-security/setup/policies/mask-email-policy.feature') { user: '#(user)', database: '#(database)' }
    * def policyName = mask.policyName

    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'mask', name: policyName });
      }
      """

  Scenario: karate-security-user sees customers.email hash-masked
    # id=1 email is 'alice@acme.io' in the fixture (customers.json)
    * def statement = "SELECT email FROM " + database + ".customers WHERE id = 1"

    # admin (unmasked) reads the real value
    * def adminRun = call read('classpath:iomete/helpers/query/run-query-v2.feature') { computeName: '#(computeName)', statement: '#(statement)' }
    * match adminRun.result.values == ['alice@acme.io']

    # the user reads it masked — retry until the value differs from the cleartext
    * def isMasked = function(r){ return r.status == 'COMPLETED' && r.resultData != null && r.resultData.values[0] != 'alice@acme.io' }
    * def result = call read('classpath:iomete/helpers/query/run-query-v2-as.feature') { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(statement)', predicate: '#(isMasked)', attempts: 15 }

    * match result.status == 'COMPLETED'
    * match result.resultData.values[0] != 'alice@acme.io'
