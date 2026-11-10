@lock=job
Feature: Data catalog, a second sync picks up what changed in Spark since the first

  The catalog keeps its own copy of the metadata and only the catalog-sync job writes it, so the
  first sync proving a table arrives says nothing about later ones. Here two tables the run's
  first sync already indexed (tests/catalog/setup/indexed-table.feature) are changed in Spark,
  one gains a commented column and the other is dropped, and the sync runs again: the catalog
  has to show the new column with its comment, and stop listing the dropped table, whose search
  document turns deleted once iom-catalog's reconciler imports the schema again.

  This costs one more sync on top of the shared one. The two tables are run-owned fixtures
  (`fixtures.catalogEvolvedTable`, `fixtures.catalogDroppedTable`) that cleanup-run drops with
  the rest of the catalog database, and the setup puts them back in their original shape, so a
  test-one repeat starts over. The feature skips itself where the catalog is switched off.

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
    * def database = indexed.database
    * def evolvedTable = indexed.evolvedTable
    * def droppedTable = indexed.droppedTable
    * def namespacePath = catalogPath + '/catalogs/' + indexed.catalogName + '/namespaces/' + database
    * def runQuery = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: indexed.computeName, statement: statement }).result }
    * def searchPath = catalogPath + '/typesense/collections/data_assets/documents/search'
    * def searchFor = function(name, deleted){ return { q: name, query_by: 'name', filter_by: 'schema:=' + database + ' && is_deleted:=' + deleted } }
    * def hasHit = function(res, name){ return res.hits != null && res.hits.filter(h => h.document.name == name).length > 0 }

  Scenario: a column added and a table dropped in Spark reach the catalog with the next sync
    * def note = 'added by karate ' + runId

    # what the first sync left: the column is not there yet, and the table to drop is listed
    # and searchable (the reconciler imports a synced schema within its poll interval)
    Given path namespacePath + '/tables/' + evolvedTable + '/meta'
    When method get
    Then status 200
    And match response.columns[*].name !contains 'note'
    Given path namespacePath + '/tables'
    When method get
    Then status 200
    And match response.tables[*].name contains droppedTable
    * configure retry = { count: 12, interval: 10000 }
    Given path searchPath
    And params searchFor(droppedTable, false)
    And retry until responseStatus == 200 && hasHit(response, droppedTable)
    When method get
    Then status 200

    # change both in Spark, then sync again with the run's own sync job
    * match runQuery('ALTER TABLE ' + indexed.catalogName + '.' + database + '.' + evolvedTable + " ADD COLUMN note STRING COMMENT '" + note + "'").status == 'COMPLETED'
    * match runQuery('DROP TABLE ' + indexed.catalogName + '.' + database + '.' + droppedTable).status == 'COMPLETED'
    * karate.call('classpath:iomete/helpers/job/run-catalog-sync.feature', { name: fixtures.catalogSyncJob })

    # Every run's sync walks every database on the target, this run's too, and iom-catalog marks
    # deleted whatever a sync's result did not tag before that sync's own updates arrive. So
    # while another run's sync is in flight the evolved table can briefly 404 and a sync that
    # listed tables before the DROP can briefly bring the dropped one back: each check polls.
    * configure retry = { count: 12, interval: 5000 }

    # the new column arrives with the comment as its description, by name and by the id the
    # listing hands out
    * def hasNote = function(res){ return res.columns != null && res.columns.filter(c => c.name == 'note' && c.description == note).length > 0 }
    Given path namespacePath + '/tables/' + evolvedTable + '/meta'
    And retry until responseStatus == 200 && hasNote(response)
    When method get
    Then status 200

    # the dropped table is marked deleted: no longer listed, and its metadata is gone
    * def listed = function(res, name){ return res.tables.filter(t => t.name == name).length > 0 }
    Given path namespacePath + '/tables'
    And retry until responseStatus == 200 && !listed(response, droppedTable) && listed(response, evolvedTable)
    When method get
    Then status 200
    * def evolvedId = response.tables.find(t => t.name == evolvedTable).id
    Given path namespacePath + '/tables/' + droppedTable + '/meta'
    And retry until responseStatus == 404
    When method get
    Then status 404

    Given path catalogPath + '/tables/' + evolvedId
    And retry until responseStatus == 200 && hasNote(response)
    When method get
    Then status 200

    # and its search document turns deleted once the reconciler imports the schema again
    * configure retry = { count: 12, interval: 10000 }
    Given path searchPath
    And params searchFor(droppedTable, true)
    And retry until responseStatus == 200 && hasHit(response, droppedTable)
    When method get
    Then status 200
    Given path searchPath
    And params searchFor(droppedTable, false)
    When method get
    Then status 200
    And assert !hasHit(response, droppedTable)
    # the console's search box sends multi-searches; the same backend answered just now
    * def block = karate.merge(searchFor(droppedTable, false), { collection: 'data_assets' })
    Given path catalogPath + '/typesense/multi_search'
    And request { searches: ['#(block)'] }
    When method post
    Then status 200
    And assert !hasHit(response.results[0], droppedTable)
