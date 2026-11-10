@ignore
Feature: Make sure the domain the suite runs in exists and has a namespace.
  Lets the suite run against an environment that was built fresh, where neither exists yet.
  Assigning a namespace also makes the platform create its bundle, which compute creation
  needs. When the local pool is empty (a planes-only target) the namespace is borrowed
  from a connected data plane instead — the same mechanism resolve-data-planes uses for
  the primary domain. Either way the assignment is shared and never deleted: it is not a
  run fixture, and unassigning would pull it out from under a concurrent run. Call it with:
    karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature',
                      { domain: 'karate' })
  Returns:
    domainId  the domain's id

  Scenario: create the domain and give it a namespace, skipping whatever already exists
    * def domainId = domain
    * def usable = function(list){ return list.filter(n => n != 'iomete-system') }

    Given url baseUrl
    And path 'api/v1/admin/domains', domainId
    When method get
    * if (responseStatus == 401 || responseStatus == 403) karate.fail('the admin API refused the token, expected status: 200, actual: ' + responseStatus)
    # a domain that doesn't exist answers 400 BAD_INPUT here, not 404
    Then assert responseStatus == 200 || responseStatus == 400 || responseStatus == 404

    # a domain named by IOMETE_DOMAIN is never created, so a typo cannot leave one behind
    * if (responseStatus != 200 && karate.get('mustExist', false)) karate.fail('domain ' + domainId + ' does not exist: IOMETE_DOMAIN must name an existing domain')
    * if (responseStatus != 200) karate.call('classpath:iomete/helpers/domain/create-domain.feature', { domainId: domainId })

    # the platform caches a user's domains for a few seconds, so a new domain answers 403 at first
    * configure retry = { count: 12, interval: 5000 }
    Given url baseUrl
    And path 'api/v1/domains', domainId, 'namespaces'
    And retry until responseStatus != 403
    When method get
    Then status 200
    * def assigned = usable(response)
    # already has one, nothing more to do
    * if (assigned.length > 0) karate.abort()

    Given url baseUrl
    And path 'api/v1/admin/namespaces'
    When method get
    Then status 200
    * def available = usable(response)

    # the local pool first — the everyday path
    * if (available.length > 0) karate.call('classpath:iomete/helpers/namespace/assign-local-namespace.feature', { domain: domainId, namespace: available[0] })
    * if (available.length > 0) karate.abort()

    # empty pool: borrow a namespace a CONNECTED plane reported, never iomete-system
    Given url baseUrl
    And path 'api/v1/admin/multi-cluster/data-planes'
    When method get
    Then status 200
    * def connected = response.filter(dp => dp.status == 'CONNECTED').map(dp => dp.id)

    Given url baseUrl
    And path 'api/v2/admin/namespaces'
    When method get
    Then status 200
    * def candidate = response.find(n => connected.includes(n.dataPlane) && n.namespace != 'iomete-system')
    # nothing assignable anywhere is a genuinely broken target — fail loudly
    * match candidate == '#notnull'
    * karate.log('local pool empty — assigning namespace ' + candidate.namespace + ' to domain ' + domainId + ' on data plane ' + candidate.dataPlane)
    * karate.call('classpath:iomete/helpers/namespace/assign-namespace.feature', { domain: domainId, namespace: candidate.namespace, dataPlane: candidate.dataPlane })
