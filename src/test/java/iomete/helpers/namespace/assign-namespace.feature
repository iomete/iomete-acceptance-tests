@ignore
Feature: Assign a namespace to a domain under a specific data plane (plumbing).
  Counterpart of unassign-namespace.feature — call it with:
    karate.call('classpath:iomete/helpers/namespace/assign-namespace.feature',
                { namespace: 'my-ns', dataPlane: 'dp-1' })
  Idempotent: 200 assigns, 409 means the (namespace, dataPlane) pair is already assigned,
  which is just as good. The v3 POST carries the data plane in the body — the v2 path-param
  assign (see ensure-domain.feature) predates multi-cluster and cannot name one.

  Scenario: assign the pair, tolerating an existing assignment
    Given url baseUrl
    And path 'api/v3/domains/' + domain + '/namespaces'
    And request { namespace: '#(namespace)', dataPlane: '#(dataPlane)' }
    When method post
    Then assert responseStatus == 200 || responseStatus == 409