@ignore
Feature: Stop a compute by id and prove it stopped.
  Cleanup helper, call it with:
    karate.call('classpath:iomete/helpers/compute/cleanup.feature', { computeId: '...' })
  A 404 means the compute was deleted between the listing and this call, which is the outcome
  the caller wanted anyway, so it is the one non-2xx answer accepted. Anything else fails: a
  teardown that reports success while a compute keeps running is the bug this exists to prevent.

  Scenario: stop the compute
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    Given url baseUrl
    And path computePath, computeId, 'stop'
    When method post
    Then assert responseStatus == 200 || responseStatus == 204 || responseStatus == 404
    * if (responseStatus == 404) karate.abort()

    # STOPPED is what the caller needs, not a POST that was accepted. Stopping an
    # already-stopped compute is a no-op that lands here immediately.
    * configure retry = { count: 10, interval: 3000 }
    Given url baseUrl
    And path computePath, computeId
    And retry until response.driverStatus == 'STOPPED'
    When method get
    Then status 200
