@lock=sql
Feature: Data catalog, a table created with SQL turns up in the catalog and can be browsed down to

  A new table travels from the engine, through the Iceberg catalog, to the catalog service the
  Data Catalog screens read. The catalog-sync job is what carries it the last step, so the
  setup feature runs that job instead of waiting for its hourly schedule, once per run, and the
  catalog features share the table it indexed (tests/catalog/setup/indexed-table.feature).

  The database and the table carry the run id, so a table another run left behind cannot answer
  for this one. The feature skips itself where the catalog is switched off.

  Background:
    * url baseUrl
    * def catalogPath = 'api/v2/domains/' + domain + '/data-catalog'
    # 501 means the catalog is not wired up here and 204 means it is. Anything else is a real
    # failure and must not pass as a skip.
    Given path catalogPath + '/enabled'
    When method get
    * if (responseStatus == 501) karate.log('data catalog is not enabled on this environment, skipping')
    * if (responseStatus == 501) karate.abort()
    Then status 204
    * def indexed = karate.callSingle('classpath:iomete/tests/catalog/setup/indexed-table.feature', { domain: domain })
    * def catalogName = indexed.catalogName
    * def database = indexed.database
    * def tableName = indexed.tableName
    * def tableId = indexed.tableId
    * def namespacePath = catalogPath + '/catalogs/' + catalogName + '/namespaces/' + database

  Scenario: a table created with SQL appears in the catalog with its columns
    Given path namespacePath + '/tables'
    When method get
    Then status 200
    And match response.tables[*].name contains tableName

    # and it arrives as a real table, with the columns it was created with
    Given path namespacePath + '/tables/' + tableName + '/meta'
    When method get
    Then status 200
    * def columns = response.columns.map(c => c.name)
    And match columns contains 'id'
    And match columns contains 'label'

    # and the same row by the id the listing handed out, which is how the screens address it
    Given path catalogPath + '/tables/' + tableId
    When method get
    Then status 200
    And match response contains { id: '#(tableId)', name: '#(tableName)', schema: '#(database)' }
