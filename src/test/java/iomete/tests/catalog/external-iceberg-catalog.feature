@lock=api
Feature: External Iceberg catalog, attached over the REST protocol and checked against a live endpoint

  An external catalog is one the platform did not provision: the caller supplies a REST uri and
  Spark talks to that endpoint directly. The suite has no third-party catalog to point at, so it
  loops back — it creates a normal internal catalog first and points the external one at the REST
  endpoint the platform serves for it, the same Iceberg REST protocol a customer's Nessie or
  Polaris would speak. The connection check is the integration under test: for an external
  catalog it runs real CREATE and DROP statements through Spark against the supplied endpoint.

  Background:
    * url baseUrl
    * def catalogsPath = 'api/v1/admin/spark/settings/catalogs'
    * def backingCatalog = 'karate_extback_' + runId
    * def externalCatalog = 'karate_external_' + runId

    # the check runs real statements through the shared Spark Connect service, which can be slow on a cold start
    * configure readTimeout = 300000

    # delete both catalogs, pass or fail; the external one first, since it points at the backing one
    * configure afterScenario =
      """
      function() {
        var firstError = null;
        var attempt = function(step) {
          try { step(); } catch (e) { if (firstError == null) firstError = e; }
        };
        var drop = function(name) {
          karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: name });
        };
        attempt(function() { drop(externalCatalog); });
        attempt(function() { drop(backingCatalog); });
        if (firstError != null) throw firstError;
      }
      """

  Scenario: an external REST catalog is attachable and its connection check runs real statements against the supplied endpoint
    # where this deployment serves the Iceberg REST protocol, and where its storage lives —
    # both read off spark_catalog instead of pinning deployment details here
    Given path catalogsPath
    When method get
    Then status 200
    * def builtIn = response.items.find(c => c.name == 'spark_catalog')
    * match builtIn == '#notnull'
    * def uriProperty = (builtIn.properties || []).find(p => p.key == 'uri')
    * match uriProperty == '#notnull'
    * def restCatalogBase = uriProperty.value.replace(/\/spark_catalog$/, '')
    * def lakehouseDir = builtIn.lakehouseDir.replace(/\/+$/, '') + '/' + backingCatalog

    # the backing catalog plays the customer-operated REST endpoint; 409 = a repeated run already made it
    * def backingRequest =
      """
      {
        name: '#(backingCatalog)',
        description: 'backing catalog for the external-catalog loopback, managed by iomete/tests/catalog/external-iceberg-catalog.feature',
        lakehouseDir: '#(lakehouseDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'internal' }
      }
      """
    Given path catalogsPath
    And request backingRequest
    When method post
    Then assert responseStatus == 200 || responseStatus == 409

    * def externalUri = restCatalogBase + '/' + backingCatalog
    * def externalRequest =
      """
      {
        name: '#(externalCatalog)',
        description: 'external Iceberg REST catalog under test, managed by iomete/tests/catalog/external-iceberg-catalog.feature',
        lakehouseDir: '#(lakehouseDir)',
        catalogType: { type: 'iceberg', subtype: 'rest', classification: 'external' },
        properties: [ { key: 'uri', value: '#(externalUri)' } ]
      }
      """

    # the check takes the catalog definition in the body, so it runs before anything is created.
    # Spark Connect starts after the platform, so wait while it still refuses connections.
    * def notUp = function(){ var r = karate.get('response'); return r && r['Create Database'] && !r['Create Database'].success && (r['Create Database'].errorMessage + '').indexOf('io exception') >= 0 }
    * configure retry = { count: 30, interval: 10000 }
    Given path 'api/v1/admin/spark/settings/catalog-connection-check'
    And request externalRequest
    And retry until responseStatus != 200 || !notUp()
    When method post
    Then status 200
    And match response['Create Database'] == { success: true, errorMessage: '##null' }
    And match response['Create Table'] == { success: true, errorMessage: '##null' }
    And match response['Drop'] == { success: true, errorMessage: '##null' }

    # control: the same check against an endpoint nothing serves must fail, or the pass above
    # proves nothing about the uri. A fresh name and an unreachable endpoint, because the REST
    # service accepts any catalog name and Spark caches a loaded catalog by name.
    * copy controlRequest = externalRequest
    * set controlRequest.name = externalCatalog + '_ctl'
    * set controlRequest.properties[0].value = 'http://localhost:1/internal/catalogs/' + backingCatalog
    Given path 'api/v1/admin/spark/settings/catalog-connection-check'
    And request controlRequest
    When method post
    Then status 200
    And match response['Create Database'].success == false

    # attaching keeps the supplied classification and uri, which computes and the console read back
    Given path catalogsPath
    And request externalRequest
    When method post
    Then assert responseStatus == 200 || responseStatus == 409

    Given path catalogsPath, externalCatalog
    When method get
    Then status 200
    And match response.catalogType == { type: 'iceberg', subtype: 'rest', classification: 'external' }
    And match response.properties contains { key: 'uri', value: '#(externalUri)' }
