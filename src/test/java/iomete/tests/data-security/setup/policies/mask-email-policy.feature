@ignore
Feature: Admin action — hash-mask the customers.email column for a user.
  Kept out of the test body so the actors read clearly: the ADMIN creates the mask policy,
  the user only runs the query. Call it with the target user and database:
    karate.call('classpath:iomete/tests/data-security/setup/policies/mask-email-policy.feature',
                { user: 'karate-security-user', database: 'spark_catalog.karate_security_db' })
  Replaces any existing policy of the same name (idempotent). Returns:
    policyName  the policy name (for teardown)
    policyId    the created policy id

  Scenario: admin creates (replaces) a MASK_HASH policy on customers.email
    * def policyName = 'karate-mask-email-e2e-' + runId
    * def maskPolicy =
      """
      {
        name: '#(policyName)',
        description: 'iomete-api-testing-suite: hash-mask the email column for the user',
        resources: [ { database: '#(database)', table: 'customers', column: 'email' } ],
        dataMaskPolicyItems: [ { dataMaskType: 'MASK_HASH', users: ['#(user)'] } ]
      }
      """
    * def policy = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'mask', policy: '#(maskPolicy)' }
    * def policyId = policy.policyId
