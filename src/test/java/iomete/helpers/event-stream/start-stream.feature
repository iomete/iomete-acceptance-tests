@ignore
Feature: Start a stopped event stream (plumbing).
  karate.call('classpath:iomete/helpers/event-stream/start-stream.feature', { streamId: '...' })

  Scenario: start it
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/event-streams', streamId, 'start'
    And request {}
    When method post
    # An ACTIVE stream also answers 204; 409 is accepted too, as "already
    # running", which is the state the caller wanted either way.
    Then match responseStatus == '#? _ == 204 || _ == 409'
