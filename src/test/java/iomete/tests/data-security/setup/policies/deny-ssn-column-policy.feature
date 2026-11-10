@ignore
Feature: Admin action — deny SELECT on the customers.ssn column for a user (column-level access).
  Kept out of the test body so the actors read clearly: the ADMIN creates the policy, the user
  only runs the query. Call it with the target user and database:
    karate.call('classpath:iomete/tests/data-security/setup/policies/deny-ssn-column-policy.feature',
                { user: 'karate-security-user', database: 'spark_catalog.karate_security_db' })
  Replaces any existing policy of the same name (idempotent). Returns:
    policyName  the policy name (for teardown)
    policyId    the created policy id

  Scenario: admin creates (replaces) a column-scoped deny on customers.ssn
    * def policyName = 'karate-deny-ssn-column-e2e-' + runId
    * def denyColumnPolicy =
      """
      {
        name: '#(policyName)',
        description: 'iomete-api-testing-suite: deny SELECT on the ssn column for the user',
        resources: [ { databases: ['#(database)'], tables: ['customers'], columns: ['ssn'] } ],
        denyPolicyItems: [ { users: ['#(user)'], accesses: ['SELECT'] } ]
      }
      """
    * def policy = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'access', policy: '#(denyColumnPolicy)' }
    * def policyId = policy.policyId
