@lock=job
Feature: A Spark job created with an explicit dataPlane reads back correctly and actually runs there

  Every existing job test goes through `helpers/job/create-job.feature` and lets the run's
  strategy (or the default plane) decide placement — so nothing else proves a job actually lands
  on the plane it was EXPLICITLY asked for. This feature proves exactly that, once per external
  deployable plane: a dynamic outline over the shared discovery
  (`helpers/dataplane/resolve-data-planes.feature`, which also assigns the domain a namespace on
  a connected plane that lacks one), so every plane gets this proof every run. On a single-plane
  target the outline is empty and nothing runs.

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

  Scenario Outline: a Spark job created with dataPlane <dataPlane> reads back correctly and runs there
    * url baseUrl
    * def jobName = 'karate-mc-job-' + dataPlane + '-' + runId
    * def jobsPath = 'api/v1/domains/' + domain + '/spark/jobs'
    # pass or fail, never leave a job behind (a leftover SCHEDULED job would keep firing; this
    # one is MANUAL, but the convention costs nothing)
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName });
      }
      """
    * def cleared = call read('classpath:iomete/helpers/job/delete-job.feature') { name: '#(jobName)' }

    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, dataPlane: dataPlane })
    * match job.dataPlane == dataPlane

    # confirm the platform's own view agrees, not just what create-job.feature returned.
    # get-by-id wraps its payload as {item, permissions} — unlike the list endpoint, which
    # returns a flat array with dataPlane at the top level
    Given path jobsPath, job.jobId
    When method get
    Then status 200
    And match response.item.dataPlane == dataPlane

    # run it — SparkPi (see create-job.feature) finishes in seconds once the driver is up; a
    # job silently stuck because it landed nowhere runnable would time out here instead of pass
    Given path jobsPath, job.jobId, 'runs'
    And request {}
    When method post
    Then status 200
    * def jobRunId = response.id

    * configure retry = { count: 60, interval: 10000 }
    Given path jobsPath, job.jobId, 'runs', jobRunId
    And retry until ['COMPLETED', 'FAILED', 'ABORTED', 'SUBMISSION_FAILED'].includes(response.driverStatus)
    When method get
    Then status 200
    And match response.driverStatus == 'COMPLETED'

    Examples:
      | karate.setup().planes |
