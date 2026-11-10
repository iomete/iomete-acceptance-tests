@ignore
Feature: Create a data-security policy (access / mask / filter). Admin action.
  Runs AS ADMIN: does not override headers, so it uses the suite default identity
  (IOMETE_TOKEN) from karate-config.js — managing policies is an admin action, never the
  user under test. Pass the policy kind and a full policy body:
    karate.call('classpath:iomete/helpers/security/create-policy.feature',
      { kind: 'mask', policy: {
          name: 'mask-email',
          resources: [ { database: 'spark_catalog.karate_security_db', table: 'customers', column: 'email' } ],
          dataMaskPolicyItems: [ { dataMaskType: 'MASK_HASH', users: ['karate-security-user'] } ]
      } })
  kind is one of: access, mask, filter (maps to /data-security/{kind}/policy). Ranger does not
  enforce name uniqueness, so this replaces any same-named policy of this kind first
  (pass replace: false to skip). Returns:
    policyId  the new policy id
    policy    the full create response

  Scenario: replace any same-named policy of this kind, then create
    * def policyPath = 'api/v1/admin/data-security/' + kind + '/policy'
    * def replace = karate.get('replace', true)
    * if (replace) karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: kind, name: policy.name })

    Given url baseUrl
    And path policyPath
    And request policy
    When method post
    Then status 201
    * def policyId = response.id
    * def policy = response
