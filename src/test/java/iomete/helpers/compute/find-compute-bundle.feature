@ignore
Feature: Find the bundle that grants access to a compute.
  The compute's own bundle, as GET compute/{id} reports it: create-compute.feature puts the
  compute in a bundle that need not be its namespace's, and access is checked against the one
  it is in. Falls back to the namespace bundle (v2 list) where the compute reports none (bundle
  authorization off for computes). Call it with:
    karate.call('classpath:iomete/helpers/compute/find-compute-bundle.feature',
                { computeName: 'karate-security', domain: 'karate' })
  Returns bundleId, or null when there is no compute of that name, so a cleanup can treat a
  compute that is already gone as nothing to do.

  Scenario: resolve the compute's bundle
    * def bundleId = null

    Given url baseUrl
    And path 'api/v2/domains', domain, 'compute'
    When method get
    Then status 200
    * def compute = response.items.find(c => c.name == computeName)
    * if (!compute) karate.abort()

    Given url baseUrl
    And path 'api/v2/domains', domain, 'compute', compute.id
    When method get
    Then status 200
    * def bundleId = response.bundle ? response.bundle.id : null
    * if (bundleId) karate.abort()

    * def plane = compute.dataPlane ? compute.dataPlane : 'default'
    Given url baseUrl
    And path 'api/v2/domains', domain, 'namespaces', 'list'
    And param dataPlane = plane
    When method get
    Then status 200
    * def entry = response.find(n => n.name == compute.namespace)
    * match entry == '#notnull'
    * def bundleId = entry.bundle.id
