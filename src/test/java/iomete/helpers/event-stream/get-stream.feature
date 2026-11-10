@ignore
Feature: Read one event stream by id, whatever the status (plumbing).
  For JS polling loops that cannot use `retry until`, call it with:
    karate.call('classpath:iomete/helpers/event-stream/get-stream.feature', { streamId: '...' })
  and read `status` and `stream` (the GET body, null unless 200). It never fails on the status,
  so a transient error is just another poll.

  Scenario: read the stream
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/event-streams', streamId
    When method get
    * def status = responseStatus
    * def stream = responseStatus == 200 ? response : null
