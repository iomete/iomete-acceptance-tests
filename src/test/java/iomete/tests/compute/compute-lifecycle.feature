@lock=spark
Feature: Compute lifecycle, a stopped compute comes back and still serves SQL

  ACTIVE is only what the platform believes, so the restarted compute is asked to run real SQL
  rather than trusted for saying it is up. An update made while it is stopped is read back from
  the restarted driver, since the stored spec only says what was asked for.

  It brings its own compute and removes it afterwards. Two cold starts make this the slowest
  scenario in the suite.

  Background:
    * url baseUrl
    # keyed per run: this scenario stops and deletes the compute, so a shared one would be
    # taken down under a concurrent run
    * def computeName = 'karate-lifecycle-compute-' + runId
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    # a compute is reused as-is once it exists, so drop one an earlier run left behind rather
    # than starting from a state this scenario did not set up
    * def clearedCompute = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }

    # teardown: never leave this compute behind, pass or fail
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
      }
      """

  Scenario: a running compute stops on request, takes an update, then restarts with it and runs a query
    # the helper waits for ACTIVE and proves the compute can really run SQL before we stop it.
    # The run's image, so the update can be read back through the V2 SQL API on any plane.
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)', singleNode: true, image: '#(sparkImage)' }

    # the restarted driver reuses the pod name, and the first driver's events stay listed for an
    # hour, so the restart is proven by a Started event the first driver did not have (counted by
    # eventCount, in case Kubernetes folds a repeat into the earlier event)
    * def driverPod = 'cc-' + computeName + '-driver'
    * def startedCount = function(events) { return events.filter(e => e.regardingObjectName == driverPod && e.reason == 'Started').reduce((n, e) => n + (e.eventCount || 1), 0) }
    Given path computePath, created.computeId, 'events'
    When method get
    Then status 200
    * def startedBefore = startedCount(response)

    Given path computePath, created.computeId, 'stop'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

    # the driver has to actually go away, which takes longer than the request that asked for it
    * configure retry = { count: 30, interval: 10000 }
    Given path computePath, created.computeId
    And retry until response.driverStatus == 'STOPPED'
    When method get
    Then status 200

    # STOPPED can come before the old driver pod is gone, and a start in that window never turns
    # ACTIVE. A gone pod stays listed for a while as Unknown.
    * configure retry = { count: 30, interval: 2000 }
    Given path computePath, created.computeId, 'instances'
    And retry until responseStatus == 200 && !response.find(p => p.name == driverPod && p.status != 'Unknown')
    When method get

    # an update only applies to a stopped compute and only reaches Spark through the restart, so
    # a Spark config set now is what the restarted driver must report below. A PUT replaces the
    # whole spec (an omitted image or config is cleared), so it sends back what GET returned.
    * def marker = 'karate-' + runId + '-' + java.util.UUID.randomUUID()
    Given path computePath, created.computeId
    When method get
    Then status 200
    * def current = response
    * def sparkConfig = current.sparkConfig
    * set sparkConfig.sparkConf = karate.merge(sparkConfig.sparkConf || {}, { 'spark.karate.marker': marker })
    * def updateRequest =
      """
      {
        namespace: '#(current.namespace)',
        dataPlane: '##(current.dataPlane)',
        nodeTypes: '#(current.nodeTypes)',
        volumeId: '##(current.volumeId)',
        autoScale: '#(current.autoScale)',
        sparkConfig: '#(sparkConfig)',
        resourceTags: '##(current.resourceTags)',
        image: '##(current.image)',
        imagePullSecrets: '##(current.imagePullSecrets)',
        queryAcceleratorEnabled: '#(current.queryAcceleratorEnabled)'
      }
      """
    Given path computePath, created.computeId
    And request updateRequest
    When method put
    Then status 200

    Given path computePath, created.computeId, 'start'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

    # a second cold start, on the same budget the create helper allows for the first
    * configure retry = { count: 60, interval: 10000 }
    Given path computePath, created.computeId
    And retry until response.driverStatus == 'ACTIVE'
    When method get
    Then status 200

    # ACTIVE is optimistic, and a compute that is up but not yet ready fails the query rather
    # than delaying it, so each attempt needs a fresh submit. The create helper already owns
    # that loop and is get-or-create, so calling it again reuses it instead of copying it.
    * def queryable = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)', singleNode: true, image: '#(sparkImage)' }

    # the restarted driver pod's Kubernetes events, as the console's events tab lists them
    * configure retry = { count: 12, interval: 5000 }
    Given path computePath, created.computeId, 'events'
    And retry until responseStatus == 200 && startedCount(response) > startedBefore
    When method get
    Then status 200

    # the update reached the running driver, not just the stored spec. On a local plane the
    # warm-up above proved v1 only; v2 goes through the driver's Arrow Flight listener, which
    # can come up later (a 500 "Compute is unreachable ... :33333" on 3.5), so resubmit briefly
    * def readMarker =
      """
      function() {
        var deadline = java.lang.System.currentTimeMillis() + 3 * 60 * 1000;
        while (true) {
          try {
            return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { computeName: computeName, statement: 'SET spark.karate.marker', retryCount: 10 });
          } catch (e) {
            if (java.lang.System.currentTimeMillis() > deadline) throw e;
            karate.log('v2 submit not ready yet, retrying:', e.message);
            java.lang.Thread.sleep(5000);
          }
        }
      }
      """
    * def conf = readMarker()
    * karate.log('SET spark.karate.marker answered:', conf.result)
    And match conf.result.values contains marker

    # both actions are on the activity list the console reads, newest first
    Given path computePath, created.computeId, 'activity'
    When method get
    Then status 200
    * def actions = response.map(a => a.action)
    And match actions contains 'STOP'
    And match actions contains 'START'
