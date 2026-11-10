@ignore
Feature: Tell the calling feature whether this build has the resource-groups API (plumbing).
  The resource-groups / resource-roles endpoints are new; older
  platforms answer 404. Call it once from a feature's Background, as admin, and skip there:
    * def probed = call read('classpath:iomete/helpers/resourcegroup/probe-resource-groups.feature')
    * if (!probed.available) { karate.log('resource-groups API not present on ' + platformVersion + ': skipping'); karate.abort() }
  The abort has to sit in the caller: karate.abort() inside a called helper only ends the helper,
  and the calling feature would carry on and fail on the missing endpoint.
  Returns:
    available  false when the list endpoint answers 404

  Scenario: probe the list endpoint
    Given url baseUrl
    And path 'api/v1/resource-groups'
    And param domain = domain
    When method get
    Then assert responseStatus == 200 || responseStatus == 404
    * def available = responseStatus != 404
