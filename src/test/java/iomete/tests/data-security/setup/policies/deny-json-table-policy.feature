@ignore
Feature: Admin action — create a deny-all access policy on a table for a user.
  Same body as deny-salaries-policy, parameterized by table (policies are format-blind).
  Call with { user, database, table }. Replaces any existing policy of the same name.
  Returns: policyName (for teardown), policyId.

  Scenario: admin creates (replaces) the deny-all policy on the given table
    * def policyName = 'karate-deny-json-table-' + runId
    * def denyPolicy =
      """
      {
        name: '#(policyName)',
        description: 'iomete-api-testing-suite: deny all operations on a metastore (USING json) table',
        resources: [ { databases: ['#(database)'], tables: ['#(table)'], columns: ['*'] } ],
        denyPolicyItems: [ { users: ['#(user)'], accesses: ['ALL'] } ]
      }
      """
    * def policy = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'access', policy: '#(denyPolicy)' }
    * def policyId = policy.policyId
