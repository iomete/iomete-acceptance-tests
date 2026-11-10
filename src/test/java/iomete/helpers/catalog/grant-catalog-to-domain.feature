@ignore
Feature: Grant a domain access to a catalog.
  Split out of tests/maintenance/setup/maintenance-catalog.feature so the grant is one step with
  one status to assert.
  Call it with:
    karate.call('classpath:iomete/helpers/catalog/grant-catalog-to-domain.feature',
                { catalogName: 'karate_maintenance', domain: 'karate' })

  Scenario: grant the domain access to the catalog
    Given url baseUrl
    And path 'api/v1/admin/spark/settings/catalogs', catalogName, 'permissions'
    And request { domains: ['#(domain)'] }
    When method post
    Then status 200
