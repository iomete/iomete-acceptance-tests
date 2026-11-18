@ignore
Feature: Turn on the privateDomains rollout flag with a global override (helper).
  Called by enable-private-domains.feature only. Setting it again is harmless. Returns set.

  Scenario: set a global override
    Given url baseUrl
    And path 'api/v1/admin/feature-flags/privateDomains/overrides'
    And request { scopeType: 'GLOBAL', enabled: true, notes: 'Turned on by the API test suite' }
    When method post
    # a build from before the flag answers that it does not know it; any other failure is a real one
    * def unknownFlag = responseStatus == 404 && karate.toString(response).contains('Rollout flag not found')
    * if (responseStatus != 200 && !unknownFlag) karate.fail('unexpected answer setting the privateDomains flag: ' + responseStatus)
    * def set = responseStatus == 200
