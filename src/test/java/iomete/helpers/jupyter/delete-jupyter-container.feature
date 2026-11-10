@ignore
Feature: Delete a Jupyter container by name.
  Cleanup helper for tests that created their own container. Call it with:
    karate.call('classpath:iomete/helpers/jupyter/delete-jupyter-container.feature', { name: 'my-container' })
  Does nothing if the container does not exist.

  Scenario: find the container and delete it
    * if (!jupyterEnabled) karate.abort()
    * def container = karate.call('classpath:iomete/helpers/jupyter/list-jupyter-containers.feature', { searchText: name }).containers.find(c => c.name == name)
    * if (!container) karate.abort()
    * def containersPath = 'api/v1/domains/' + domain + '/jupyter-containers'

    Given url baseUrl
    And path containersPath, container.id
    When method delete
    Then assert responseStatus >= 200 && responseStatus < 300
