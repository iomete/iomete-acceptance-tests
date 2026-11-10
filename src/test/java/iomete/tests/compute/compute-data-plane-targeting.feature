@lock=spark
Feature: A compute created with an explicit dataPlane reads back correctly and actually warms up there

  Every existing compute test in this suite goes through `helpers/compute/create-compute.feature`
  and lets the run's strategy (or the default plane) decide placement — so nothing else proves a
  compute actually lands on the plane it was EXPLICITLY asked for. This feature proves exactly
  that, once per external deployable plane: a dynamic outline over the shared discovery
  (`helpers/dataplane/resolve-data-planes.feature`, which also assigns the domain a namespace on
  a connected plane that lacks one), so every plane gets this proof every run — mixed-mode
  hashing only samples planes, this is the guaranteed per-plane smoke. On a single-plane target
  the outline is empty and nothing runs.

  @setup
  Scenario: the external planes this domain can deploy to
    # a quick look first: with no connected external plane there is nothing to discover, and the
    # callSingle below can queue for minutes behind the shared computes' warm-up
    Given url baseUrl
    And path 'api/v1/admin/multi-cluster/data-planes'
    When method get
    Then status 200
    * def hasExternal = !!response.find(dp => dp.id != 'default' && dp.status == 'CONNECTED')
    * def discovered = hasExternal ? karate.callSingle('classpath:iomete/helpers/dataplane/resolve-data-planes.feature', { baseUrl: baseUrl, domain: domain, strategy: 'mixed' }) : { planes: [] }
    * def planes = discovered.planes.filter(dp => dp != 'default').map(dp => ({ dataPlane: dp }))

  Scenario Outline: a compute created with dataPlane <dataPlane> reads back correctly and warms up there
    * url baseUrl
    # the plane is in the name so two planes' computes cannot collide on the reuse-by-name path
    * def computeName = 'karate-mc-compute-' + dataPlane + '-' + runId
    # pass or fail, never leave a warm compute behind on a remote plane
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
      }
      """

    * def compute = karate.call('classpath:iomete/helpers/compute/create-compute.feature', { name: computeName, dataPlane: dataPlane })
    # create-compute already proved readiness (driver ACTIVE + a real warm-up query, on the
    # right API for the plane) — reaching this line at all is half the proof

    Given path 'api/v2/domains/' + domain + '/compute', compute.computeId
    When method get
    Then status 200
    And match response.dataPlane == dataPlane

    Examples:
      | karate.setup().planes |
