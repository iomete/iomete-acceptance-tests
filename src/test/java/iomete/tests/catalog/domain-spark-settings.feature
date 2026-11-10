@lock=api
Feature: Domain Spark settings, the properties and catalogs a domain's jobs and computes run with

  One main flow through the domain-scoped endpoints: update a Spark property and a catalog the
  domain owns, then read both back. The catalog and the property key are this run's own, and
  both are removed afterwards.

  Background:
    * url baseUrl
    * def settingsPath = 'api/v1/domains/' + domain + '/spark/settings'
    * def catalogsPath = 'api/v1/admin/spark/settings/catalogs'
    * def catalogName = 'karate_domain_settings_' + runId

    * def propertyKey = 'spark.karate.domainSettings.' + runId

    # each step runs even when an earlier one throws, so a failed restore never leaks the catalog
    * configure afterScenario =
      """
      function() {
        var firstError = null;
        var attempt = function(step) {
          try { step(); } catch (e) { if (firstError == null) firstError = e; }
        };
        attempt(function() {
          karate.call('classpath:iomete/helpers/domain/remove-spark-property.feature', { key: propertyKey });
        });
        attempt(function() {
          karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: catalogName });
        });
        if (firstError != null) throw firstError;
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
        description: 'managed by iomete/tests/catalog/domain-spark-settings.feature',
        lakehouseDir: '#(lakehouseDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' }
      }
      """
    Given path catalogsPath
    And request createRequest
    When method post
    Then status 200

    # the domain endpoints only edit a catalog the domain has access to and owns
    * def granted = call read('classpath:iomete/helpers/catalog/grant-catalog-to-domain.feature') { catalogName: '#(catalogName)', domain: '#(domain)' }

    Given path catalogsPath, catalogName, 'owner'
    And request { domainId: '#(domain)' }
    When method put
    Then status 200

  Scenario: a domain updates a Spark property and its catalog, and reads both back
    * def property = { key: '#(propertyKey)', value: 'yes', isSecret: false }

    # a PUT replaces every property of the domain, so the current ones are sent back with it
    Given path settingsPath, 'properties'
    When method get
    Then status 200
    * def updatedProperties = response.concat([property])

    Given path settingsPath, 'properties'
    And request updatedProperties
    When method put
    Then status 200

    Given path settingsPath, 'catalogs', catalogName
    When method get
    Then status 200
    * def updateRequest = response
    * set updateRequest.description = 'updated by domain-spark-settings'
    * set updateRequest.properties = (response.properties || []).concat([{ key: 'karate.edited', value: 'yes' }])

    Given path settingsPath, 'catalogs', catalogName
    And request updateRequest
    When method put
    Then status 200

    Given path settingsPath, 'properties'
    When method get
    Then status 200
    And match response contains property

    Given path settingsPath, 'catalogs', catalogName
    When method get
    Then status 200
    And match response.description == 'updated by domain-spark-settings'
    And match response.properties contains { key: 'karate.edited', value: 'yes' }
