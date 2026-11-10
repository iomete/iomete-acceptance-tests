@ignore
Feature: Admin action — create a deny-all access policy on the salaries table for a user.
  Kept out of the test body so the actors read clearly: the ADMIN creates the policy, the
  user only runs the query. Call it with the target user and database:
    karate.call('classpath:iomete/tests/data-security/setup/policies/deny-salaries-policy.feature',
                { user: 'karate-security-user', database: 'spark_catalog.karate_security_db' })
  Replaces any existing policy of the same name (idempotent). Returns:
    policyName  the policy name (for teardown)
    policyId    the created policy id

  Scenario: admin creates (replaces) the deny-all policy on salaries
    * def policyName = 'karate-deny-salaries-e2e-' + runId
    * def denyPolicy =
      """
      {
        name: '#(policyName)',
        description: 'iomete-api-testing-suite: deny all operations on the salaries table',
        resources: [ { databases: ['#(database)'], tables: ['salaries'], columns: ['*'] } ],
        denyPolicyItems: [ { users: ['#(user)'], accesses: ['ALL'] } ]
      }
      """
    * def policy = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'access', policy: '#(denyPolicy)' }
    * def policyId = policy.policyId
