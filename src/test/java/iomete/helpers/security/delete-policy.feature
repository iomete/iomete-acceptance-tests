@ignore
Feature: Delete a data-security policy by id or name. Admin action.
  Works for all three policy kinds — pass kind = access | mask | filter (maps to the
  /data-security/{kind}/policy endpoints). Call it with either identifier:
    karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'mask', name: 'mask-email' })
    karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'access', policyId: 42 })
  Does nothing if no matching policy exists.

  Scenario: find the policy of this kind, then delete it
    * def basePath = 'api/v1/admin/data-security/' + kind + '/policy'
    * def wantId = karate.get('policyId')
    * def wantName = karate.get('name')

    Given url baseUrl
    And path basePath
    When method get
    Then status 200
    * def found = wantId != null ? response.find(p => p.id == wantId) : response.find(p => p.name == wantName)
    * if (!found) karate.abort()

    Given url baseUrl
    And path basePath, found.id
    When method delete
    Then status 204
