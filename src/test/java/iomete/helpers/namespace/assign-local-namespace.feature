@ignore
Feature: Assign a local-plane namespace to a domain (plumbing).
  The v2 path-param assign, which predates multi-cluster and cannot name a data plane —
  it always targets the local pool. Counterpart of assign-namespace.feature (v3, per plane).
  Call it with:
    karate.call('classpath:iomete/helpers/namespace/assign-local-namespace.feature',
                { domain: 'karate-secondary', namespace: 'spark-resources-1' })

  Scenario: assign it, tolerating an existing assignment
    Given url baseUrl
    And path 'api/v2/domains', domain, 'namespaces', namespace
    When method post
    # 409 means another run assigned it first
    Then assert responseStatus == 200 || responseStatus == 409
