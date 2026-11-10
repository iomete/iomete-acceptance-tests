@ignore
Feature: Remove a namespace assignment from a domain, for a specific data plane.
  Cleanup helper for tests that assign a namespace under an explicit data plane — call it with:
    karate.call('classpath:iomete/helpers/namespace/unassign-namespace.feature', { namespace: 'my-ns', dataPlane: 'dp-1' })
  Does nothing if the (namespace, dataPlane) pair is not currently assigned — checked via the
  v3 listing rather than just calling delete and tolerating any error status, since a 403
  ("not allowed in domain") covers both "never assigned" and a genuine permission problem, and
  swallowing that blindly would hide the second.

  The delete itself goes through v2 (v3 has no DELETE of its own — assign/remove stayed on v2,
  with dataPlane as an additive query param).

  Scenario: check the assignment is actually there, then remove it
    Given url baseUrl
    And path 'api/v3/domains/' + domain + '/namespaces'
    When method get
    Then status 200
    * def assigned = response.find(n => n.namespace == namespace && n.dataPlane == dataPlane)
    * if (!assigned) karate.abort()

    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/namespaces', namespace
    And param dataPlane = dataPlane
    When method delete
    Then status 200
