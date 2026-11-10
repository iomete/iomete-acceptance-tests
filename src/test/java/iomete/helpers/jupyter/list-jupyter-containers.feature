@ignore
Feature: List the domain's Jupyter containers matching a name, whoever created them.
  The listing only returns the caller's own containers (view MY) or everyone else's (view
  SHARED), so this asks for both. Call it with:
    karate.call('classpath:iomete/helpers/jupyter/list-jupyter-containers.feature', { searchText: 'karate-' })
  Returns:
    containers  the matching containers from both views

  Scenario: list both views
    * def containersPath = 'api/v1/domains/' + domain + '/jupyter-containers'

    Given url baseUrl
    And path containersPath
    And params { searchText: '#(searchText)', view: 'MY', size: 100 }
    When method get
    Then status 200
    * def mine = response.items

    Given url baseUrl
    And path containersPath
    And params { searchText: '#(searchText)', view: 'SHARED', size: 100 }
    When method get
    Then status 200
    * def containers = mine.concat(response.items)
