@ignore
Feature: Find an event stream by its exact name (helper).
  Usage: karate.call('classpath:iomete/helpers/event-stream/find-stream.feature', { name: '...' }).stream
  Returns: the stream, or null if there is none.

  Scenario: look it up
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/event-streams'
    And params { searchText: '#(name)' }
    When method get
    Then status 200
    # The search matches partial names, so keep only the exact match.
    * def stream = response.items.find(x => x.name == name) || null
