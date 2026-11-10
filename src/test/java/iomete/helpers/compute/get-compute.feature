@ignore
Feature: Read one compute by id, whatever the status (plumbing).
  For JS polling loops that cannot use `retry until`, call it with:
    karate.call('classpath:iomete/helpers/compute/get-compute.feature', { computeId: '...' })
  and read `status` and `compute` (the GET body, null unless 200). It never fails on the status,
  so a transient error is just another poll.

  Scenario: read the compute
    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/compute', computeId
    When method get
    * def status = responseStatus
    * def compute = responseStatus == 200 ? response : null
