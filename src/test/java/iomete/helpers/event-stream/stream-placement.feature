@ignore
Feature: Pick the namespace and bundle a new event stream goes into (helper).
  Usage: karate.call('classpath:iomete/helpers/event-stream/stream-placement.feature')
  Returns: namespace, bundleId.

  Creating a stream needs both. This is the same lookup create-compute.feature does.

  Scenario: pick the namespace and bundle
    # Make sure the domain exists (a freshly rebuilt environment has none yet).
    * karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domain })

    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/namespaces'
    When method get
    Then status 200
    * def namespaces = response.filter(n => n != 'iomete-system')
    And match namespaces == '#[_ > 0]'
    * def namespace = namespaces[0]

    # Streams only run on the built-in data plane, so prefer a namespace on it.
    Given url baseUrl
    And path 'api/v3/domains/' + domain + '/namespaces'
    When method get
    Then status 200
    * def localNamespaces = response.filter(n => n.dataPlane == 'default' && n.namespace != 'iomete-system')
    * if (localNamespaces.length > 0) namespace = localNamespaces[0].namespace

    Given url baseUrl
    And path 'api/v1/bundles'
    And params { scope: 'OWNED', domain: '#(domain)' }
    When method get
    Then status 200
    * def bundle = response.items[0]
    And match bundle == '#notnull'
    * def bundleId = bundle.bundleId
