@lock=sql
Feature: SQL — the schema browser lists this run's database and table down to its snapshots

  The SQL editor's left-hand tree (catalogs, namespaces, tables, columns, Iceberg snapshots)
  is served by iom-sql through the platform's shared Arrow Flight schema server
  (iom-spark-connect), not by the compute a query runs on. A run creates its database and
  seeds a table through the V2 query API on the shared compute, and this feature checks the
  tree shows them: that is the metastore, the schema server and iom-sql agreeing, which no fake
  backend can reproduce. The admin copy of the tree walks the same server with metadata
  authorization off, so it is not exercised separately.

  Skips when the ARROW_FLIGHT_FOR_DB_EXPLORER flag is off (`arrowFlightDbExplorerEnabled` in
  karate-config.js): every schema endpoint answers 409 then, and the console browses through
  another service.

  Background:
    * url baseUrl
    * if (!arrowFlightDbExplorerEnabled) karate.log('ARROW_FLIGHT_FOR_DB_EXPLORER is off, the schema browser is not served by iom-sql here, skipping')
    * if (!arrowFlightDbExplorerEnabled) karate.abort()

    # seeds this run's database from setup/data/ fixtures, once per run
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def catalogName = testData.database.split('.')[0]
    * def namespace = testData.database.split('.')[1]
    # the columns the fixture seeded, in its order, so data and assertion cannot drift
    * def expectedColumns = Object.keys(testData.employees[0])
    * def schemaPath = 'api/v2/domains/' + domain + '/sql/schema'
    # the schema server caches what it listed; this run's database is new, so ask it to look again
    * def fresh = { forceRefresh: true }

  Scenario: the domain tree goes from the catalog list down to the seeded table and its snapshots
    # the one namespace listing: /namespaces/v2 walks every catalog of the domain (forceRefresh
    # refreshes each), and /catalogs/{c}/namespaces is the same server call for one catalog
    Given path schemaPath, 'namespaces', 'v2'
    And params fresh
    When method get
    Then status 200
    And match response[*].catalog contains catalogName
    * def catalog = response.find(c => c.catalog == catalogName)
    And match catalog.errorMessage == '##null'
    And match catalog.namespaces contains namespace
    # each row carries its catalog's full settings (catalogInfo): no secret may come back plain.
    # iom-core masks access and secret keys and secret-named properties (not token-ttl).
    * def plainSecret = function(c) { return (c.credentials && [c.credentials.accessKey, c.credentials.secretKey].some(v => v && v != '********')) || (c.properties || []).some(p => /password|token|secret|key/i.test(p.key) && !/token-ttl/i.test(p.key) && p.value && p.value != '********') }
    And match response.filter(r => r.catalogInfo && plainSecret(r.catalogInfo)).map(r => r.catalog) == []

    Given path schemaPath, 'catalogs', catalogName, 'namespaces', namespace, 'tables'
    And params fresh
    When method get
    Then status 200
    And match response[*].name contains 'employees'
    * def table = response.find(t => t.name == 'employees')
    And match table.isView == false

    # the table with its columns, as the fixture created it
    Given path schemaPath, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees'
    And params fresh
    When method get
    Then status 200
    And match response.error == '##null'
    * def columns = response.columns.map(c => c.name)
    And match columns == expectedColumns
    # the detail reads "Provider" off DESCRIBE EXTENDED (an empty string when absent); Iceberg
    # is what makes the snapshots call below answer
    And match response.provider.toLowerCase() == 'iceberg'

    # the seed's INSERT is the newest snapshot (the list is newest first, and nothing else
    # writes this table); its summary is a JSON string with Iceberg's counters
    Given path schemaPath, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees', 'snapshots-and-refs'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And match response[0].snapshot_id == '#string'
    And match response[0].operation == 'append'
    * def summary = karate.fromString(response[0].summary)
    And match summary['added-records'] == '' + testData.employees.length
