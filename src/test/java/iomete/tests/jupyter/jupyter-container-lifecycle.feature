@lock=spark
Feature: Jupyter containers, a container comes up, serves JupyterLab, goes away on stop and comes back on start

  ACTIVE is only what the platform believes, so the running container is asked for
  JupyterLab's own status through the endpoint the console opens, with the token the
  platform handed out. Stopping it has to take that endpoint down again, and starting it
  after an update has to bring it back. Logs and events come from the running pod, so they
  are read while it is up.

  It brings its own container and removes it afterwards.

  Background:
    * if (!jupyterEnabled) { karate.log('skipping: jupyterContainers is off on ' + baseUrl); karate.abort() }
    * url baseUrl
    # keyed per run: this scenario stops and deletes the container
    * def containerName = 'karate-jupyter-' + runId
    * def containersPath = 'api/v1/domains/' + domain + '/jupyter-containers'

    # drop one an earlier attempt left behind rather than start from a state this scenario did not set up
    * def cleared = call read('classpath:iomete/helpers/jupyter/delete-jupyter-container.feature') { name: '#(containerName)' }

    # teardown: never leave this container behind, pass or fail
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/jupyter/delete-jupyter-container.feature', { name: containerName });
      }
      """

  Scenario: a new container serves JupyterLab with its token, stops serving it once stopped, and serves it again once updated and started
    * karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domain })
    * def targetDataPlane = dataPlaneFor(containerName)

    # the namespace selects the plane, so take one on the target plane, or the local one by default
    Given path 'api/v3/domains/' + domain + '/namespaces'
    And param dataPlane = targetDataPlane
    When method get
    Then status 200
    * def usable = response.filter(n => n.namespace != 'iomete-system')
    * def onPlane = usable.filter(n => n.dataPlane == (targetDataPlane ? targetDataPlane : 'default'))
    * def namespace = (onPlane[0] || usable[0]).namespace
    * match namespace == '#string'

    # the container is created inside a bundle, like a compute
    Given path 'api/v1/bundles'
    And params { scope: 'OWNED', domain: '#(domain)' }
    When method get
    Then status 200
    * def bundleId = response.items[0].bundleId
    * match bundleId == '#string'

    # an idle JupyterLab needs far less than a Spark driver, so it gets the suite's smallest type
    * def picked = karate.call('classpath:iomete/helpers/compute/pick-node-types.feature', { preferredDriver: 'karate-jupyter', preferredExecutor: 'karate-exec' })

    * def createRequest =
      """
      {
        name: '#(containerName)',
        namespace: '#(namespace)',
        nodeType: '#(picked.driverNodeType)',
        bundleId: '#(bundleId)'
      }
      """
    * if (targetDataPlane) karate.set('createRequest', '$.dataPlane', targetDataPlane)

    Given path containersPath
    And request createRequest
    When method post
    Then status 201
    * def containerId = response.id

    # the image is large and the node pool scales from zero, so the first start takes minutes
    * configure retry = { count: 60, interval: 10000 }
    Given path containersPath, containerId
    And retry until response.status == 'ACTIVE' || response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'ACTIVE'
    And match response.endpoints.jupyterLab == '#string'

    # a local-plane endpoint is relative to the console, a remote one carries the plane's own host
    * def labUrl = response.endpoints.jupyterLab
    * def labBase = labUrl.startsWith('http') ? labUrl : baseUrl.replace(/\/$/, '') + '/' + labUrl
    * def statusUrl = labBase.replace('?', '/api/status?')

    # The gateway can hold a lab request open while the pod starts or stops, and a read timeout
    # ends a `retry until`, so the lab is polled here with a short timeout, asking again on one.
    * def pollLab =
      """
      function(url, done) {
        karate.configure('readTimeout', 10000);
        var status = 0;
        for (var i = 0; i < 18; i++) {
          try {
            status = karate.http(url).get().status;
            if (done(status)) break;
          } catch (e) {
            if (!(e.message + '').includes('timed out')) throw e;
            karate.log('lab did not answer, asking again:', e.message);
          }

          java.lang.Thread.sleep(10000);
        }

        karate.configure('readTimeout', 60000);
        return status;
      }
      """

    # the lab is reached with its own token only, so it never sees the platform admin token or cookies
    * configure headers = {}
    * configure cookies = null

    # ACTIVE can come before the server listens, so give JupyterLab a little time of its own
    * match pollLab(statusUrl, function(s) { return s == 200 }) == 200
    Given url statusUrl
    When method get
    Then status 200
    And match response.started == '#string'
    And match response.kernels == '#number'

    # the token is what lets the request in, so the same call without it is refused
    # the token call left a session cookie behind, so drop it or the lab still lets us in
    * configure cookies = null
    * def statusWithoutToken = statusUrl.substring(0, statusUrl.indexOf('?'))
    Given url statusWithoutToken
    When method get
    Then assert responseStatus == 401 || responseStatus == 403

    * configure headers = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # logs are the pod's own output, read through the data plane, so a running lab has some
    * configure retry = { count: 12, interval: 10000 }
    Given url baseUrl
    And path containersPath, containerId, 'logs'
    And param range = '15m'
    And retry until responseStatus == 200 && response.length > 0
    When method get
    Then status 200
    And match each response == { date: '#number', logLine: '#string' }

    # the pod's Kubernetes events: it was at least scheduled
    Given url baseUrl
    And path containersPath, containerId, 'events'
    When method get
    Then status 200
    And match response == '#[_ > 0]'

    Given url baseUrl
    And path containersPath, containerId, 'stop'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

    Given url baseUrl
    And path containersPath, containerId
    When method get
    Then status 200
    And match response.status == 'STOPPED'

    # the pod goes away a little after the request that asked for it
    * configure headers = {}
    * def stoppedLabStatus = pollLab(statusUrl, function(s) { return s != 200 })
    * karate.log('lab answered after stop:', stoppedLabStatus)
    # 0 means the lab never answered at all, which proves nothing
    * assert stoppedLabStatus != 0 && stoppedLabStatus != 200

    * configure headers = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # a stopped container takes an update, and the change is what it comes back with
    * def updateTag = { key: 'karate-run', value: '#(runId)' }
    Given url baseUrl
    And path containersPath, containerId
    When method get
    Then status 200
    * def current = response
    * def updateRequest = { name: '#(current.name)', namespace: '#(current.namespace)', nodeType: '#(current.nodeType)', config: '#(current.config)', resourceTags: ['#(updateTag)'] }
    * if (current.dataPlane) karate.set('updateRequest', '$.dataPlane', current.dataPlane)

    Given url baseUrl
    And path containersPath, containerId
    And request updateRequest
    When method put
    Then status 200
    And match response.resourceTags contains updateTag

    Given url baseUrl
    And path containersPath, containerId, 'start'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

    * configure retry = { count: 60, interval: 10000 }
    Given url baseUrl
    And path containersPath, containerId
    And retry until response.status == 'ACTIVE' || response.status == 'FAILED'
    When method get
    Then status 200
    And match response.status == 'ACTIVE'
    And match response.resourceTags contains updateTag
    * def restartedLabUrl = response.endpoints.jupyterLab
    * def restartedBase = restartedLabUrl.startsWith('http') ? restartedLabUrl : baseUrl.replace(/\/$/, '') + '/' + restartedLabUrl
    * def restartedStatusUrl = restartedBase.replace('?', '/api/status?')

    # and the lab is served again, by the restarted pod
    * configure headers = {}
    * configure cookies = null
    * match pollLab(restartedStatusUrl, function(s) { return s == 200 }) == 200
    Given url restartedStatusUrl
    When method get
    Then status 200
    And match response.started == '#string'

    * configure cookies = null
    * configure headers = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    Given url baseUrl
    And path containersPath, containerId
    When method delete
    Then assert responseStatus >= 200 && responseStatus < 300

    Given url baseUrl
    And path containersPath
    And params { searchText: '#(containerName)', size: 100 }
    When method get
    Then status 200
    And match response.items[*].name !contains containerName
