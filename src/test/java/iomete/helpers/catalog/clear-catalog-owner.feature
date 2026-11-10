@ignore
Feature: Clear a catalog's owner, which also has iom-maintenance disable maintenance on it.
  Call with:
    karate.call('classpath:iomete/helpers/catalog/clear-catalog-owner.feature', { catalogName: 'karate_x_...' })
  404 passes so a teardown stays green when the catalog is already gone.

  Scenario: clear the owner, tolerating a catalog that does not exist
    Given url baseUrl
    And path 'api/v1/admin/spark/settings/catalogs', catalogName, 'owner'
    When method delete
    Then assert responseStatus == 200 || responseStatus == 204 || responseStatus == 404
