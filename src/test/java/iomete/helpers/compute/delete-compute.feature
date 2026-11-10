@ignore
Feature: Delete a compute by name.
  Cleanup helper for tests that created their own compute — call it with:
    karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: 'my-compute' })
  Does nothing if the compute does not exist.

  Scenario: find the compute and delete it
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    Given url baseUrl
    And path computePath
    # this listing is not paginated and returns every compute (the paginated one is /list/paginated)
    When method get
    Then status 200
    * def compute = response.items.find(c => c.name == name)
    * if (!compute) karate.abort()

    Given url baseUrl
    And path computePath, compute.id
    When method delete
    Then status 204