@ignore
Feature: A table of this run that the data catalog has indexed, invoked once per run via karate.callSingle.
  The catalog only learns about a table through the catalog-sync job, and a sync costs a driver
  cold start plus a walk over the whole metastore, so the catalog features share one table and one
  sync instead of each paying for their own:
    def indexed = karate.callSingle('classpath:iomete/tests/catalog/setup/indexed-table.feature', { domain: domain })
  Returns catalogName, database (bare, no catalog prefix), tableName, qualified (catalog.db.table),
  tableId (the catalog's own id for the row) and computeName, plus evolvedTable and droppedTable,
  the two tables tests/catalog/catalog-resync.feature changes in Spark before syncing again.

  The database, the tables and the sync job are run-owned fixtures (karate-config.js,
  `fixtures.catalogDb`, `fixtures.catalogTable`, `fixtures.catalogEvolvedTable`,
  `fixtures.catalogDroppedTable` and `fixtures.catalogSyncJob`), dropped by
  `make cleanup-run`. The database and tables are named per image leg as well as per run, and the sync always
  runs, see the note at the call.

  Callers check `GET .../data-catalog/enabled` before asking for this: on a 501 target there is
  nothing to index into.

  Scenario: create the table if it is missing, sync the catalog, wait for the row
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = sqlCompute.computeName
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }
    * def catalogName = fixtures.catalogDb.split('.')[0]
    * def database = fixtures.catalogDb.split('.')[1]
    * def tableName = fixtures.catalogTable
    * def qualified = fixtures.catalogDb + '.' + tableName
    * def tablesPath = 'api/v2/domains/' + domain + '/data-catalog/catalogs/' + catalogName + '/namespaces/' + database + '/tables'

    * def dbCreated = runQuery('CREATE DATABASE IF NOT EXISTS ' + fixtures.catalogDb)
    * match dbCreated.status == 'COMPLETED'
    * def tableCreated = runQuery('CREATE TABLE IF NOT EXISTS ' + qualified + ' (id INT, label STRING)')
    * match tableCreated.status == 'COMPLETED'
    # catalog-resync adds a column to one and drops the other; replaced and recreated here so a
    # test-one repeat under the same run id starts from the original shape again
    * def evolvedTable = fixtures.catalogEvolvedTable
    * def droppedTable = fixtures.catalogDroppedTable
    * match runQuery('CREATE OR REPLACE TABLE ' + fixtures.catalogDb + '.' + evolvedTable + ' (id INT)').status == 'COMPLETED'
    * match runQuery('CREATE TABLE IF NOT EXISTS ' + fixtures.catalogDb + '.' + droppedTable + ' (id INT)').status == 'COMPLETED'

    # Always synced, even when the listing already has a row of this name: cleanup-run drops the
    # Spark table but the catalog keeps its row until the next sync, so a test-one repeat under
    # the same run id would otherwise pass on the stale row of the table it just dropped. The
    # database and table names carry the image too, so the two legs of one run never answer for
    # each other.
    * karate.call('classpath:iomete/helpers/job/run-catalog-sync.feature', { name: fixtures.catalogSyncJob })

    # the sync writes the catalog rows as it goes, so they are there once it has finished; the
    # bounded poll is for the listing catching up, and it is what every catalog feature waits on
    * configure retry = { count: 12, interval: 5000 }
    Given url baseUrl
    And path tablesPath
    And retry until responseStatus == 200 && response.tables.filter(t => t.name == tableName).length > 0
    When method get
    Then status 200
    * def table = response.tables.find(t => t.name == tableName)
    * match table == '#notnull'
    * def tableId = table.id
