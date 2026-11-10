@ignore
Feature: Create (or reuse) a compute and wait until it can really execute SQL.
  Generic helper — callers pass the compute name and, optionally, a custom image,
  extra spark configs, a volume to attach, single-node deployment, the query
  accelerator (Apache Comet — Spark 4+ images only), or a specific data plane to target (an id
  from GET /api/v1/admin/multi-cluster/data-planes, 'dp-1' below is just an example):
    karate.call('classpath:iomete/helpers/compute/create-compute.feature',
                { name: 'my-compute', image: 'repo/spark:tag', sparkConf: { 'key': 'value' } })
    karate.call('classpath:iomete/helpers/compute/create-compute.feature',
                { name: 'my-compute', volumeId: '...', singleNode: true })
    karate.call('classpath:iomete/helpers/compute/create-compute.feature',
                { name: 'my-compute', image: 'repo/spark:4-tag', queryAcceleratorEnabled: true })
    karate.call('classpath:iomete/helpers/compute/create-compute.feature',
                { name: 'my-compute', dataPlane: 'dp-1' })
  Returns computeName, computeId and computeDataPlane (the resolved plane, null when local —
  callers running their own queries pick v1/v2 by it, like the warm-up below does).
  A compute that already exists is reused as-is, so these
  options only take effect on the initial create. A caller passing dataPlane brings its own
  compute (see tests/compute/compute-data-plane-targeting.feature) rather than adding to the
  suite's shared ones — same footprint as any other per-run compute in this suite.
  Without an explicit dataPlane, the run's data-plane STRATEGY decides (dataPlaneFor in
  karate-config.js): 'local' places nothing, 'external'/'mixed' spread the per-run computes
  across the detected planes. An explicit caller argument always wins over the strategy.

  Scenario: get or create the compute, then prove readiness with a warm-up query
    # a rebuilt environment has no domain or namespace yet, and a compute needs both
    * karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domain })

    * def computeName = name
    * def computePath = 'api/v2/domains/' + domain + '/compute'
    # an explicit dataPlane wins; otherwise the run's strategy assigns one (null under 'local')
    * def explicitDataPlane = karate.get('dataPlane')
    * def targetDataPlane = explicitDataPlane ? explicitDataPlane : dataPlaneFor(computeName)
    * if (targetDataPlane && !explicitDataPlane) karate.log('data-plane strategy "' + dataPlaneStrategy + '" places compute ' + computeName + ' on data plane ' + targetDataPlane)

    # deployment namespace assigned to the domain — the default (no explicit data plane) path
    # is untouched from before this helper knew about data planes at all
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/namespaces'
    When method get
    Then status 200
    * def namespaces = response.filter(n => n != 'iomete-system')
    And match namespaces == '#[_ > 0]'
    * def deploymentNamespace = namespaces[0]

    # a caller asking for a SPECIFIC data plane needs a namespace that actually belongs to it —
    # v1 above is data-plane-blind, so a namespace name picked from it could silently belong to
    # a different data plane than the one this compute is meant to land on. v3 disambiguates.
    Given url baseUrl
    And path 'api/v3/domains/' + domain + '/namespaces'
    And param dataPlane = targetDataPlane
    When method get
    Then status 200
    * if (targetDataPlane && response.length == 0) karate.fail('data plane "' + targetDataPlane + '" has no namespace assigned to domain ' + domain)
    * if (targetDataPlane) deploymentNamespace = (response.filter(n => n.namespace != 'iomete-system')[0] || response[0]).namespace

    # No target plane: still prefer a namespace on the local ('default') plane. The v1 pick
    # above is plane-blind, and a namespace on a disconnected plane makes the create 500
    # ("Failed to call lakehouse-agent"). Falls back to the v1 pick when no row is tagged
    # 'default' (a legacy target whose rows carry no dataPlane).
    * def localNamespaces = targetDataPlane ? [] : response.filter(n => n.dataPlane == 'default' && n.namespace != 'iomete-system')
    * if (!targetDataPlane && localNamespaces.length > 0) deploymentNamespace = localNamespaces[0].namespace

    # bundle of that namespace (compute must be created inside a bundle)
    Given url baseUrl
    And path 'api/v1/bundles'
    And params { scope: 'OWNED', domain: '#(domain)' }
    When method get
    Then status 200
    * def bundle = response.items[0]
    And match bundle == '#notnull'

    # the suite's own small types, or the smallest this environment has
    * def picked = karate.call('classpath:iomete/helpers/compute/pick-node-types.feature', { preferredDriver: karate.get('driverType', 'karate-driver'), preferredExecutor: karate.get('executorType', 'karate-exec') })
    * def driverNodeType = picked.driverNodeType
    * def executorNodeType = picked.executorNodeType

    # base request; image and sparkConf are added only when the caller provided them
    * def createRequest =
      """
      {
        name: '#(computeName)',
        description: 'compute for iomete-api-testing-suite, managed by iomete/helpers/compute/create-compute.feature',
        namespace: '#(deploymentNamespace)',
        bundleId: '#(bundle.bundleId)',
        nodeTypes: { driver: '#(driverNodeType)', executor: '#(executorNodeType)', maxExecutors: 1, singleNodeDeployment: false },
        autoScale: { enabled: true, idleTimeoutInSeconds: 1800 }
      }
      """
    * def customImage = karate.get('image')
    * if (customImage) karate.set('createRequest', '$.image', customImage)
    * def customSparkConf = karate.get('sparkConf')
    * if (customSparkConf) karate.set('createRequest', '$.sparkConfig', { sparkConf: customSparkConf })
    * def attachedVolumeId = karate.get('volumeId')
    * if (attachedVolumeId) karate.set('createRequest', '$.volumeId', attachedVolumeId)
    * def singleNode = karate.get('singleNode')
    * if (singleNode) karate.set('createRequest', '$.nodeTypes.singleNodeDeployment', true)
    * def queryAcceleratorEnabled = karate.get('queryAcceleratorEnabled')
    * if (queryAcceleratorEnabled) karate.set('createRequest', '$.queryAcceleratorEnabled', true)
    * if (targetDataPlane) karate.set('createRequest', '$.dataPlane', targetDataPlane)
    # the plane in the description makes a red run attributable in the UI
    * if (targetDataPlane) karate.set('createRequest', '$.description', createRequest.description + ' | dataPlane: ' + targetDataPlane)

    # Create if missing; 409 means it already exists. Retried because a freshly installed
    # platform answers 500 until its data plane has registered (about a minute).
    * configure retry = { count: 20, interval: 6000 }
    Given url baseUrl
    And path computePath
    And request createRequest
    And retry until responseStatus < 500
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    # look up its id
    Given url baseUrl
    And path computePath
    When method get
    Then status 200
    * def compute = response.items.find(c => c.name == computeName)
    * match compute == '#notnull'
    * def computeId = compute.id

    # Reuse guard: the compute name is keyed only by image TAG (computeSuffix), and a 409
    # reuses the existing compute as-is. So two image refs sharing a tag — e.g. a run that
    # defaulted to the dev image then re-ran with the correct published one — collapse onto
    # one compute and every retry silently runs the wrong image. Fail loudly, naming the
    # compute to delete. Guarded on compute.image being present so a list response without
    # the field degrades to no-op rather than a false failure.
    * if (customImage && compute.image && compute.image != customImage) karate.fail('compute "' + computeName + '" already exists with image ' + compute.image + ', but ' + customImage + ' was requested — delete this compute and re-run (the name is keyed by image tag, so same-tag images reuse it)')

    # Same reuse trap as the image above: a 409 reuses the compute wherever it lives. Guarded
    # on compute.dataPlane being present, so a list response without the field degrades to no-op.
    * if (targetDataPlane && compute.dataPlane && compute.dataPlane != targetDataPlane) karate.fail('compute "' + computeName + '" already exists on data plane ' + compute.dataPlane + ', but ' + targetDataPlane + ' was requested — delete this compute and re-run')

    # start it — tolerate errors when it is already running/starting
    Given url baseUrl
    And path computePath, compute.id, 'start'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 500

    # what the platform reports about the compute, logged right before either wait gives up
    # a diagnostics error must never replace the compute's own failure
    * def logDiagnostics = function(why) { try { karate.call('classpath:iomete/helpers/compute/log-compute-diagnostics.feature', { domain: domain, computeId: computeId, computeName: computeName, why: why }) } catch (e) { karate.log('compute diagnostics failed: ' + redact(e.message)) } }

    # wait until the driver is ACTIVE and its executor runs (cold start can take a few minutes):
    # the driver reports ACTIVE before it starts the executor, which the warm-up would pay for.
    # A JS loop rather than `retry until`, so the diagnostics can still run when it times out.
    * def driverDeadlineMs = 10 * 60 * 1000
    * def waitUntilDriverActive =
      """
      function() {
        var deadline = java.lang.System.currentTimeMillis() + driverDeadlineMs;
        var status = null;
        while (java.lang.System.currentTimeMillis() < deadline) {
          var read = karate.call('classpath:iomete/helpers/compute/get-compute.feature', { domain: domain, computeId: computeId });
          // a status without executorsState only waits for the driver
          var executors = read.compute ? read.compute.executorsState : null;
          var running = executors ? (executors.RUNNING || 0) : 0;
          status = read.compute ? read.compute.driverStatus + ', ' + running + ' executor(s) running' : 'HTTP ' + read.status;
          if (read.compute && read.compute.driverStatus == 'ACTIVE' && (singleNode || !executors || running > 0)) return true;
          java.lang.Thread.sleep(10000);
        }
        var failure = 'compute ' + computeName + ': not up after ' + (driverDeadlineMs / 60000) + ' min, last status ' + status;
        logDiagnostics(failure);
        return failure;
      }
      """
    * def driverFailure = waitUntilDriverActive()
    * if (driverFailure !== true) karate.fail(driverFailure)

    # ACTIVE is optimistic — computes report it before they can actually execute SQL.
    # Prove readiness by running a real warm-up query until it completes.
    #
    # The v1 SQL editor reaches a compute by its in-cluster address, so it can never reach
    # one on a remote data plane — v2 routes through the plane's public gRPC listener. Local
    # computes keep the v1 warm-up, which is what keeps the suite's v1 coverage real; a
    # remote v2 warm-up also round-trips a result through the plane's own storage.
    * def warmUpQueryFeature = queryFeatureFor(targetDataPlane)
    #
    # Deliberately a hand-rolled loop, NOT Karate's `retry until`: a not-yet-ready
    # compute makes the submitted query FAIL (not merely respond slowly), so each
    # attempt must SUBMIT A FRESH query. Karate's `retry until` replays one HTTP
    # request and can't resubmit the submit+poll pair, so it can't express this.
    # The budget is WALL-CLOCK, not attempts: an attempt against a compute that hangs
    # (e.g. its executor never scheduled on a quota-starved plane) costs its whole poll
    # (retryCount 5 ≈ 15s) where one that is merely not ready fails in milliseconds — a
    # fixed attempt count ballooned past Karate's 30-minute event timeout once, which
    # kills the JVM mid-run with no teardown. 5 minutes: a compute still not ready by then
    # fails fast, and the workflow's retry pass of failed features gets another attempt.
    * def warmUpDeadlineMs = 5 * 60 * 1000
    * def warmUpIntervalMs = 3000
    * def waitUntilReady =
      """
      function() {
        var deadline = java.lang.System.currentTimeMillis() + warmUpDeadlineMs;
        var reason = null;
        for (var i = 1; java.lang.System.currentTimeMillis() < deadline; i++) {
          try {
            karate.call(warmUpQueryFeature, { domain: domain, computeName: computeName, statement: 'SELECT 1', retryCount: 5 });
            return true;
          } catch (e) {
            var leftSec = java.lang.Math.max(0, (deadline - java.lang.System.currentTimeMillis()) / 1000) | 0;
            // Karate nests each called feature's error; the last "Error:" line is the query's own
            var errorLines = (e.message + '').split('\n').filter(l => l.trim().startsWith('Error:'));
            reason = (errorLines.length ? errorLines[errorLines.length - 1].trim().substring(7) : (e.message + '').split('\n')[0]).substring(0, 300);
            karate.log('warm-up query failed (attempt ' + i + ', ' + leftSec + 's of budget left), compute not ready yet: ' + redact(reason));
            java.lang.Thread.sleep(warmUpIntervalMs);
          }
        }
        var failure = 'compute ' + computeName + ': warm-up query still failing after ' + (warmUpDeadlineMs / 60000) + ' min, last error: ' + redact(reason);
        logDiagnostics(failure);
        return failure;
      }
      """
    * def warmUpFailure = waitUntilReady()
    * if (warmUpFailure !== true) karate.fail(warmUpFailure)

    # for callers that run their own queries and must pick the same v1/v2 path (null = local)
    * def computeDataPlane = targetDataPlane ? targetDataPlane : null