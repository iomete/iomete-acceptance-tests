@ignore
Feature: Admin action — row-filter the customers table to region 'AMER' for a user (RLS).
  Kept out of the test body so the actors read clearly: the ADMIN creates the row-filter
  policy, the user only runs the query. Call it with the target user and database:
    karate.call('classpath:iomete/tests/data-security/setup/policies/filter-region-policy.feature',
                { user: 'karate-security-user', database: 'spark_catalog.karate_security_db' })
  Replaces any existing policy of the same name (idempotent). Returns:
    policyName  the policy name (for teardown)
    policyId    the created policy id

  Scenario: admin creates (replaces) a row-filter limiting customers to region 'AMER'
    * def policyName = 'karate-filter-region-e2e-' + runId
    * def filterPolicy =
      """
      {
        name: '#(policyName)',
        description: 'iomete-api-testing-suite: restrict customers rows to the AMER region for the user',
        resources: [ { database: '#(database)', table: 'customers' } ],
        rowFilterPolicyItems: [ { filterExpr: "region = 'AMER'", users: ['#(user)'] } ]
      }
      """
    * def policy = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'filter', policy: '#(filterPolicy)' }
    * def policyId = policy.policyId
