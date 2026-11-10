@ignore
Feature: Shared event stream for the Event Stream tests — invoked via karate.callSingle.
  Named by eventStream in karate-config.js: per run where the run has its own domain, whose
  teardown deletes it, and shared by every run in the fixed domain of an older platform.
  Callers gate on helpers/dataplane/has-local-plane.feature first: external streams
  deploy through the local plane only, and the create below answers 500 where there is none.
  Returns: streamName, streamId, ingestPath.

  Scenario: get or create the shared event stream, and wait until it is ACTIVE
    * def streamName = eventStream
    * def streamsPath = 'api/v1/domains/' + domain + '/event-streams'
    * def placement = karate.call('classpath:iomete/helpers/event-stream/stream-placement.feature')

    # 409 means an earlier run already built it, which is the reuse this depends on.
    Given url baseUrl
    And path streamsPath
    # The loader pauses ingest once the disk under its volume is half full, and with no volume
    # that is the node's own disk, which images alone can fill that far on a one-node install.
    * def config = { envVars: { DISK_BACKPRESSURE_PERCENT: '95', DISK_RECOVER_PERCENT: '90' } }
    And request { name: '#(streamName)', namespace: '#(placement.namespace)', bundleId: '#(placement.bundleId)', replicas: 1, config: '#(config)' }
    When method post
    Then match responseStatus == '#? _ == 201 || _ == 409'

    # Find it by name whether this run created it or an earlier one did.
    Given url baseUrl
    And path streamsPath
    And params { searchText: '#(streamName)' }
    When method get
    Then status 200
    * def mine = response.items.filter(x => x.name == streamName)
    And match mine == '#[1]'
    * def streamId = mine[0].id
    # a reused stream left on another plane would never come up, so fail naming it
    * def streamPlane = mine[0].dataPlane
    * if (streamPlane && streamPlane != 'default') karate.fail('event stream "' + streamName + '" is on data plane ' + streamPlane + ', but streams only run on the built-in plane — delete it and re-run')

    # A stream that an earlier run left STOPPED has to be started again before it can ingest.
    * def current = mine[0].status
    * if (current == 'STOPPED' || current == 'FAILED') karate.call('classpath:iomete/helpers/event-stream/start-stream.feature', { streamId: streamId })

    # Pods have to be pulled and scheduled, so this is minutes, not seconds.
    * configure retry = { count: 40, interval: 5000 }
    Given url baseUrl
    And path streamsPath, streamId
    And retry until response.status == 'ACTIVE'
    When method get
    Then status 200
    And match response.status == 'ACTIVE'

    # Taken from the API rather than built here, so a change to the path shape is followed
    # instead of silently testing a dead URL. It comes back with a literal "{host}" prefix for
    # the console to fill in; stripping that leaves the path under baseUrl.
    * def ingestPath = response.endpoints.ingest.replace('{host}', '')
    * match ingestPath == '#regex ^/data-plane/.+/event-stream/.+/ingest$'
