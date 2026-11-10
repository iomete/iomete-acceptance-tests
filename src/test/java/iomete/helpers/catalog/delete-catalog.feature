@ignore
Feature: Delete a Spark catalog by name; a no-op when it is already gone.
  Call with:
    karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: 'karate_x_...' })
  404 passes so teardowns and repeated test-one runs stay green.

  Scenario: delete the catalog, tolerating one that does not exist
    Given url baseUrl
    And path 'api/v1/admin/spark/settings/catalogs', catalogName
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404
