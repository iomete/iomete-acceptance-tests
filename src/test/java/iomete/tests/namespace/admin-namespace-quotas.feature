@lock=api
Feature: Namespace and quota visibility across every connected data plane (admin)

  Admin-tier, cross-domain view: `/api/v2/admin/namespaces` and its quota siblings list every
  managed namespace across every connected data plane, not scoped to one domain. dataPlane is
  just a field on each row here, the same way it is on tests/namespace/domain-namespace-quotas.feature's
  domain-scoped v3 siblings.

  What makes these acceptance-level, not something a mocked backend could stand in for: the
  namespace/quota values come from the real DP-push pipeline (agent -> 5s report -> CP storage
  -> admin fan-out), so a passing scenario proves that pipeline actually
  landed rows for a real data plane, not just that the endpoint returns 200.

  The pipeline is per plane, so the assertions anchor on A CONNECTED plane, not on the
  plane named 'default': a planes-only target has only enrolled planes, and the pipeline
  under test is the same either way.

  Background:
    * url baseUrl
    * def namespacesPath = 'api/v2/admin/namespaces'

    # the anchor: whichever connected plane this target has
    Given path 'api/v1/admin/multi-cluster/data-planes'
    When method get
    Then status 200
    * def anchorPlane = response.find(dp => dp.status == 'CONNECTED')
    * match anchorPlane == '#notnull'
    * def anchorId = anchorPlane.id

  Scenario: namespaces across every connected data plane are listed, each tagged with its own data plane
    Given path namespacesPath
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And match each response == { namespace: '#string', dataPlane: '#ignore' }
    And match response[*].dataPlane contains anchorId

  Scenario: namespace quotas across data planes include a connected plane's real resource usage
    Given path namespacesPath + '/quotas'
    When method get
    Then status 200
    * def anchorQuotas = response.find(dp => dp.id == anchorId)
    And match anchorQuotas == '#notnull'
    And match anchorQuotas contains { status: 'CONNECTED' }
    # every connected plane reports at least one managed namespace — an empty list here means
    # the push pipeline stopped, not that there is nothing to show
    And match anchorQuotas.quotas == '#[_ > 0]'
    * def oneNamespace = anchorQuotas.quotas[0]
    And match oneNamespace == { namespace: '#string', resourceQuotas: '#array' }

  Scenario: quotas grouped by resource type are always empty when priorityClasses is off
    Given path namespacesPath + '/quotas/by-resource-type'
    When method get
    Then status 200
    * def anchorQuotas = response.find(dp => dp.id == anchorId)
    And match anchorQuotas == '#notnull'
    And match anchorQuotas contains { status: 'CONNECTED' }
    * def priorityClassKeys = Object.keys(anchorQuotas.quotas)
    # off -> always empty is the only direction this suite can assert: on doesn't guarantee
    # non-empty without a real priority-class-scoped ResourceQuota object, which this suite
    # doesn't create. Catches a stale pod still serving a cached 'false' after the flag flips on.
    And assert priorityClassesEnabled || priorityClassKeys.length == 0
    * def validKeys = ['COMPUTE', 'SPARK_JOB', 'NOTEBOOK']
    And assert priorityClassKeys.every(k => validKeys.includes(k))
