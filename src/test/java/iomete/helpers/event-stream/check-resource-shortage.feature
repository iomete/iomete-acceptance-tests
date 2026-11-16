@ignore
Feature: Check whether a starting event stream is held back by a namespace quota or node capacity shortage.
  Called while a stream starts, so a full quota fails the wait early:
    karate.call('classpath:iomete/helpers/event-stream/check-resource-shortage.feature',
                { streamId: '...', streamName: 'my-stream', namespace: '...', since: <epoch ms> })
  Only events since the wait began count. Returns shortage (see resource-shortage.js),
  whose giveUp says when to stop waiting. It never fails on a status.

  Scenario: read the stream's events

    # the StatefulSet records a pod the quota refuses as a FailedCreate event
    Given url baseUrl
    And path 'api/v1/domains', domain, 'event-streams', streamId, 'events'
    When method get
    * def events = responseStatus == 200 && Array.isArray(response) ? response : []

    * def resourceShortage = read('classpath:iomete/helpers/namespace/resource-shortage.js')
    * def shortage = resourceShortage({ subject: 'event stream ' + streamName, namespace: namespace, events: events, since: since })
