@lock=spark
Feature: Event Stream — scale, stop, update and start a stream

  What this checks:
  - A new stream starts one pod, with both of its containers running.
  - Scaling to 2 adds a second pod.
  - Stopping removes all pods.
  - An update made while stopped (back to 1 replica) takes effect on the next start.
  - Deleting the stream removes it.

  Each check reads what Kubernetes reports (pods, containers, events), not just the
  stream's saved settings.

  Why this stream is its own: other tests send data to the shared stream "karate-es".
  Stopping or scaling that one would break them, so this test creates and deletes its own.

  Cost: each pod uses 2 CPU and 4 GiB, so the test needs 8 GiB free while scaled to 2.

  Not tested here (covered by iom-cluster's own tests): error codes for invalid
  actions, input validation, and the code-examples endpoint.

  Background:
    # Event streams only run on the built-in data plane. Skip if the target has none.
    * def planes = karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature')
    * if (!planes.hasLocalPlane) karate.log('external event streams need a local (default) data plane and this target has none — skipping')
    * if (!planes.hasLocalPlane) karate.abort()

    * url baseUrl
    * def streamName = 'karate-es-lc-' + runId
    * def streamsPath = 'api/v1/domains/' + domain + '/event-streams'
    # Stop and delete can take up to 60 seconds to answer.
    * configure readTimeout = 90000
    * def findStream = function() { return karate.call('classpath:iomete/helpers/event-stream/find-stream.feature', { name: streamName }).stream }
    # Remove any stream left by an earlier attempt, and remove ours when the test ends.
    # A failed delete fails the test: no cleanup job removes streams, and one holds up to 8 GiB.
    * def removeStream =
      """
      function() {
        var s = findStream();
        if (!s) return;
        var r = karate.call('classpath:iomete/helpers/event-stream/delete-stream.feature', { streamId: s.id });
        if (!r.deleted) karate.fail('could not delete event stream ' + streamName + ' (HTTP ' + r.code + ')');
      }
      """
    * removeStream()
    * configure afterScenario = function() { removeStream() }

  Scenario: create, scale, stop, update, start and delete a stream
    # Step 1: create the stream with one pod.
    * def placement = karate.call('classpath:iomete/helpers/event-stream/stream-placement.feature')
    Given path streamsPath
    And request { name: '#(streamName)', namespace: '#(placement.namespace)', bundleId: '#(placement.bundleId)', replicas: 1 }
    When method post
    Then status 201
    * def streamId = response.id
    * def podPrefix = 'es-' + streamName + '-'

    # Starting pods takes a few minutes. A JS loop rather than `retry until`, so the
    # diagnostics can still run when it times out. Every 30s it also checks for quota
    # refusals and gives up early once they have lasted 2 minutes.
    * def activeDeadlineMs = 5 * 60 * 1000
    * def waitUntilActive =
      """
      function() {
        var startedMs = java.lang.System.currentTimeMillis();
        var deadline = startedMs + activeDeadlineMs;
        var status = null;
        var failure = null;
        for (var i = 1; failure == null && java.lang.System.currentTimeMillis() < deadline; i++) {
          try {
            var read = karate.call('classpath:iomete/helpers/event-stream/get-stream.feature', { streamId: streamId });
            status = read.stream ? read.stream.status : 'HTTP ' + read.status;
          } catch (e) {
            status = 'request failed: ' + redact((e.message + '').split('\n')[0]);
          }
          if (status == 'ACTIVE') return true;
          if (i % 6 == 0) {
            // a failed check only skips this round, it never replaces the stream's own failure
            try {
              var check = karate.call('classpath:iomete/helpers/event-stream/check-resource-shortage.feature', { streamId: streamId, streamName: streamName, namespace: placement.namespace, since: startedMs });
              if (check.shortage && check.shortage.refused) karate.log('stream ' + streamName + ' is waiting on the namespace quota: ' + redact(check.shortage.text));
              if (check.shortage && check.shortage.giveUp) failure = 'stream ' + streamName + ': gave up after ' + ((java.lang.System.currentTimeMillis() - check.shortage.firstRefusalMs) / 60000 | 0) + ' min of quota refusals, last status ' + status;
            } catch (e) {
              karate.log('quota check failed: ' + redact((e.message + '').split('\n')[0]));
            }
          }
          if (failure == null) java.lang.Thread.sleep(5000);
        }
        if (failure == null) failure = 'stream ' + streamName + ': not ACTIVE after ' + (activeDeadlineMs / 60000) + ' min, last status ' + status;
        try {
          var d = karate.call('classpath:iomete/helpers/event-stream/log-stream-diagnostics.feature', { streamId: streamId, streamName: streamName, namespace: placement.namespace, why: failure, since: startedMs });
          if (d.shortage) failure = redact(d.shortage.text) + '\nDetails: ' + failure;
        } catch (e) {
          karate.log('stream diagnostics failed: ' + redact(e.message));
        }
        return failure;
      }
      """
    * def activeFailure = waitUntilActive()
    * if (activeFailure !== true) karate.fail(activeFailure)

    * configure retry = { count: 24, interval: 5000 }
    Given path streamsPath, streamId, 'pods'
    And retry until response.length == 1 && response[0].status == 'Running'
    When method get
    Then status 200
    And match response[0].name == podPrefix + '0'

    # The pod runs two containers: the ingest server and the table loader.
    Given path streamsPath, streamId, 'pods', podPrefix + '0', 'containers'
    And retry until response.length == 2 && response.every(c => c.status == 'Running')
    When method get
    Then status 200
    And match response[*].name contains only ['http-server', 'table-loader']

    # Kubernetes events for the stream are listed.
    Given path streamsPath, streamId, 'events'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And assert response.some(e => e.regardingObjectName && e.regardingObjectName.startsWith('es-' + streamName))

    # Step 2: scale to 2. A second pod starts and the stream reports 2 of 2 ready.
    Given path streamsPath, streamId, 'scale'
    And request { replicas: 2 }
    When method post
    Then status 204

    # The second pod needs another 2 CPU / 4 GiB, which can mean adding a node first, so it gets
    # the same 5 minutes as the first pod.
    * configure retry = { count: 60, interval: 5000 }
    Given path streamsPath, streamId, 'pods'
    And retry until response.length == 2 && response.every(p => p.status == 'Running')
    When method get
    Then status 200

    Given path streamsPath, streamId
    And retry until response.ready == '2/2'
    When method get
    Then status 200

    # Step 3: stop the stream.
    Given path streamsPath, streamId, 'stop'
    And request {}
    When method post
    Then status 204

    # Pods take up to 3 minutes to shut down, so wait up to 5 minutes for STOPPED.
    * configure retry = { count: 60, interval: 5000 }
    Given path streamsPath, streamId
    And retry until response.status == 'STOPPED'
    When method get
    Then status 200
    * def stopped = response

    # No pods are left.
    Given path streamsPath, streamId, 'pods'
    And retry until response.length == 0
    When method get
    Then status 200

    # Step 4: update the stopped stream back to 1 replica and add a tag.
    # Send all current settings back: a missing field can reset to its default.
    * def tags = (stopped.resourceTags || []).concat([{ key: 'karate-run', value: runId }])
    Given path streamsPath, streamId
    And request { namespace: '#(stopped.namespace)', volumeId: '#(stopped.volumeId)', replicas: 1, config: '#(stopped.config)', resourceTags: '#(tags)' }
    When method put
    Then status 200
    And match response.replicas == 1
    And match response.resourceTags contains { key: 'karate-run', value: '#(runId)' }

    # Step 5: start it again. The update only takes effect now: one pod, not two.
    Given path streamsPath, streamId, 'start'
    And request {}
    When method post
    Then status 204

    Given path streamsPath, streamId
    And retry until response.status == 'ACTIVE' && response.ready == '1/1'
    When method get
    Then status 200

    * configure retry = { count: 24, interval: 5000 }
    Given path streamsPath, streamId, 'pods'
    And retry until response.length == 1 && response[0].status == 'Running'
    When method get
    Then status 200

    # Step 6: delete the stream. It is gone afterwards.
    Given path streamsPath, streamId
    When method delete
    Then status 204

    Given path streamsPath, streamId
    When method get
    Then status 404
