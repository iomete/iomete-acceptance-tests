@lock=api
Feature: Admin catalog actions, editing a catalog and managing which domains can use it

  Two main flows on a catalog the scenario creates and removes itself: an admin edits it, and a
  domain is granted it, owns it for maintenance, then has the owner and access removed.

  Background:
    * url baseUrl
    * def catalogsPath = 'api/v1/admin/spark/settings/catalogs'
    * def catalogName = 'karate_admin_actions_' + runId

    * configure afterScenario =
      """
      function() {
        // clear the owner first, so a failed scenario does not leave maintenance on for a deleted catalog
        if (karate.get('ownerSet', false)) {
          karate.call('classpath:iomete/helpers/catalog/clear-catalog-owner.feature', { catalogName: catalogName });
        }
        karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: catalogName });
      }
      """

    # start from a fresh catalog when IOMETE_RUN_ID is pinned and an earlier run left one behind
    * def deleted = call read('classpath:iomete/helpers/catalog/delete-catalog.feature') { catalogName: '#(catalogName)' }

    # storage differs per environment, so the location is derived from the built-in catalog
    Given path catalogsPath
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * match builtIn == '#notnull'
    * def lakehouseDir = builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + catalogName

    * def createRequest =
      """
      {
        name: '#(catalogName)',
        description: 'managed by iomete/tests/catalog/catalog-admin-actions.feature',
        lakehouseDir: '#(lakehouseDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' }
      }
      """
    Given path catalogsPath
    And request createRequest
    When method post
    Then status 200

  Scenario: an admin edits a catalog's description, properties and tags
    Given path catalogsPath, catalogName
    When method get
    Then status 200
    * def updateRequest = response
    * set updateRequest.description = 'updated by catalog-admin-actions'

    Given path catalogsPath, catalogName
    And request updateRequest
    When method put
    Then status 200

    Given path catalogsPath, catalogName, 'properties'
    And request { upsertedProperties: [ { key: 'karate.edited', value: 'yes' } ], deletedPropertyKeys: [] }
    When method put
    Then status 200

    Given path catalogsPath, catalogName, 'resource-tags'
    And request { resourceTags: [ { key: 'usage', value: 'acceptance' } ] }
    When method put
    Then status 200

    Given path catalogsPath, catalogName
    When method get
    Then status 200
    And match response.description == 'updated by catalog-admin-actions'
    And match response.properties contains { key: 'karate.edited', value: 'yes' }
    And match response.resourceTags == [ { key: 'usage', value: 'acceptance' } ]

  Scenario: a domain is granted the catalog, owns it for maintenance, then loses it
    Given path catalogsPath, 'permissions', 'bulk'
    And request [ { catalogName: '#(catalogName)', domains: ['#(domain)'] } ]
    When method post
    Then status 200

    Given path catalogsPath, 'domain', domain, 'permissions'
    When method get
    Then status 200
    And match response contains catalogName

    Given path catalogsPath, catalogName, 'owner'
    And request { domainId: '#(domain)' }
    When method put
    Then status 200
    * def ownerSet = true

    # maintenance can only be turned on by the owning domain
    Given path 'api/v1/domains', domain, 'compaction/catalogs', catalogName, 'config'
    And request { maintenanceEnabled: { value: 'true' } }
    When method put
    Then status 200

    Given path catalogsPath, catalogName
    When method get
    Then status 200
    And match response.properties contains { key: 'iomete.maintenance.enabled', value: 'true' }

    # clearing the owner has iom-core ask iom-maintenance to disable it
    Given path catalogsPath, catalogName, 'owner'
    When method delete
    Then status 200

    Given path catalogsPath, catalogName
    When method get
    Then status 200
    And match response.ownerDomainId == '##null'
    And match response.properties contains { key: 'iomete.maintenance.enabled', value: 'false' }

    Given path catalogsPath, catalogName, 'permissions', domain
    When method delete
    Then status 200

    Given path catalogsPath, catalogName, 'permissions'
    When method get
    Then status 200
    And match response !contains domain
