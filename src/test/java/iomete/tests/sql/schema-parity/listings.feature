@lock=sql
Feature: SQL schema parity — V1 and V2 list the same namespaces and tables

  A client moving from V1 to V2 must see the same tree: the namespaces of a catalog and of the
  domain, and the tables of a namespace, with and without metadata. The catalog-wide table
  list is left out: it walks every database of the catalog and can time out on a shared target.
  V1 here is the deprecated native routes (see setup/parity.feature). Other features and runs
  create and drop databases on the same target at any time, so the scenario compares a
  database of its own (two tables and a view), created through the shared SQL compute and
  dropped afterwards, rather than whole listings; lists are compared as sets, since V2 sorts
  where V1 does not. Then a table created after V2 listed the database must show up on the V1
  route customers call (forwarded to V2) without asking for a refresh, since V1 never cached.
  Last, a database created after V2 listed the namespaces must be listed by V2 as soon as it is
  asked for a refresh: `forceRefresh` used to clear only the tables cache, so V2 kept its
  namespace list for up to 10 minutes and missed the new database's tables.

  Skips when ARROW_FLIGHT_FOR_DB_EXPLORER is off: every V2 schema endpoint answers 409 then.

  Background:
    * url baseUrl
    * if (!arrowFlightDbExplorerEnabled) karate.log('ARROW_FLIGHT_FOR_DB_EXPLORER is off, V2 schema routes are not served here, skipping')
    * if (!arrowFlightDbExplorerEnabled) karate.abort()
    # route prefixes, this run's seeded database and table, and the comparison helpers
    * def ctx = karate.call('classpath:iomete/tests/sql/schema-parity/setup/parity.feature', { domain: domain })
    * def v1Native = ctx.v1Native
    * def v1Forwarded = ctx.v1Forwarded
    * def v2 = ctx.v2
    * def catalogName = ctx.catalogName
    * def fresh = ctx.fresh
    * def runQuery = ctx.runQuery
    * def tableKeys = ctx.tableKeys
    * def inCatalog = ctx.inCatalog

  Scenario: V1 and V2 list the same namespaces and tables

    # ===== Setup: a database of this scenario's own, two tables and a view =====
    * def db = 'karate_parity_list_' + runId
    * def full = catalogName + '.' + db
    # a second database, created only in step 4
    * def dbNew = 'karate_parity_new_' + runId
    * def fullNew = catalogName + '.' + dbNew
    # DROP DATABASE ... CASCADE leaves the tables behind in this catalog (setup/ddl-db.feature),
    # so the view and the tables go first
    * configure afterScenario = function(){ runQuery('DROP VIEW IF EXISTS ' + full + '.big_orders'); runQuery('DROP TABLE IF EXISTS ' + full + '.orders'); runQuery('DROP TABLE IF EXISTS ' + full + '.customers'); runQuery('DROP TABLE IF EXISTS ' + full + '.late'); runQuery('DROP DATABASE IF EXISTS ' + full); runQuery('DROP TABLE IF EXISTS ' + fullNew + '.fresh'); runQuery('DROP DATABASE IF EXISTS ' + fullNew) }
    * runQuery('CREATE DATABASE IF NOT EXISTS ' + full)
    # a cancelled run never reached afterScenario, so its `late` table would join the listing below
    * runQuery('DROP TABLE IF EXISTS ' + full + '.late')
    # and its step 4 database: left in place, step 1 would cache it and step 4 would find it
    # whether forceRefresh works or not
    * runQuery('DROP TABLE IF EXISTS ' + fullNew + '.fresh')
    * runQuery('DROP DATABASE IF EXISTS ' + fullNew)
    * runQuery('CREATE TABLE IF NOT EXISTS ' + full + '.orders (id INT, amount DOUBLE)')
    * runQuery('CREATE TABLE IF NOT EXISTS ' + full + '.customers (id INT, name STRING)')
    * runQuery('CREATE OR REPLACE VIEW ' + full + '.big_orders AS SELECT id FROM ' + full + '.orders WHERE amount > 100')
    * def expected = ([db + '.big_orders (view)', db + '.customers', db + '.orders']).sort()
    # the shared schema server can take a few seconds to see objects the compute just created,
    # even with forceRefresh, so the V2 reads below wait for them
    * configure retry = { count: 10, interval: 3000 }

    # ===== 1. Namespace lists: the database is in all three =====
    # the database is listed by the catalog's, the domain's flat and the domain's grouped namespaces

    # V1 (native): list the namespaces of the catalog
    Given path v1Native, 'catalogs', catalogName, 'namespaces'
    When method get
    Then status 200
    And match response.map(n => n.namespace) contains db

    # V2: list the namespaces of the catalog
    Given path v2, 'catalogs', catalogName, 'namespaces'
    And params fresh
    And retry until responseStatus == 200 && response.map(n => n.namespace).includes(db)
    When method get
    Then status 200
    And match response.map(n => n.namespace) contains db

    # V1 (native): list every namespace of the domain
    Given path v1Native, 'namespaces'
    When method get
    Then status 200
    And match inCatalog(response).map(n => n.namespace) contains db

    # V2: list every namespace of the domain
    Given path v2, 'namespaces'
    And params fresh
    And retry until responseStatus == 200 && inCatalog(response).map(n => n.namespace).includes(db)
    When method get
    Then status 200
    And match inCatalog(response).map(n => n.namespace) contains db

    # V1 (native): list namespaces grouped by catalog
    Given path v1Native, 'namespaces', 'v2'
    When method get
    Then status 200
    And match response.find(c => c.catalog == catalogName).namespaces contains db
    * def v1CatalogInfo = response.find(c => c.catalog == catalogName).catalogInfo

    # V2: list namespaces grouped by catalog
    Given path v2, 'namespaces', 'v2'
    And params fresh
    And retry until responseStatus == 200 && response.find(c => c.catalog == catalogName).namespaces.includes(db)
    When method get
    Then status 200
    And match response.find(c => c.catalog == catalogName).namespaces contains db
    # and the catalog's settings as V1 lists them, properties and masked credentials included
    # (V2 dropped them before iomete-kotlin-monorepo#4690)
    * def infoMatch = karate.match(response.find(c => c.catalog == catalogName).catalogInfo, v1CatalogInfo)
    * if (platformAtLeast('4.0.3') && !infoMatch.pass) karate.fail('V2 catalogInfo differs from V1: ' + infoMatch.message)

    # ===== 2. Tables of the database: same tables and view on V1 and V2 =====
    # its tables and view, the same on both, with and without metadata

    # V1 (native): list the tables of the test database
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables'
    When method get
    Then status 200
    And match tableKeys(response) == expected

    # V2: list the tables of the test database
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables'
    And params fresh
    And retry until responseStatus == 200 && response.length >= expected.length
    When method get
    Then status 200
    And match tableKeys(response) == expected

    # V1 (native): list the tables with metadata of the test database
    Given path v1Native, 'catalogs', catalogName, 'namespaces', db, 'tables'
    And param includeMetadata = true
    When method get
    Then status 200
    * def v1WithMetadata = response.map(t => t.name).sort()

    # V2: list the tables with metadata of the test database
    Given path v2, 'catalogs', catalogName, 'namespaces', db, 'tables'
    And param includeMetadata = true
    When method get
    Then status 200
    And match response.map(t => t.name).sort() == v1WithMetadata

    # ===== 3. A table created after V2 listed the database: the forwarded V1 route sees it =====
    # both fixes below ship with 4.0.2
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the V2 schema fixes these checks compare, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()
    # V2 has just listed the database, so the schema server holds that listing in its cache. V1
    # never cached, so the V1 route customers call (forwarded to V2) must not answer from it: it
    # lists a table created now without being asked for a refresh
    * runQuery('CREATE TABLE IF NOT EXISTS ' + full + '.late (id INT)')

    # V1 (forwarded to V2): list the tables of the test database, no forceRefresh
    Given path v1Forwarded, 'catalogs', catalogName, 'namespaces', db, 'tables'
    And retry until responseStatus == 200 && response.map(t => t.name).includes('late')
    When method get
    Then status 200
    And match response.map(t => t.name) contains 'late'

    # ===== 4. A database created after V2 listed the namespaces: forceRefresh sees it =====
    # the namespace refresh comes from the schema server's arrow-server
    * if (!ctx.schemaServerFixed) karate.log('the schema server predates the namespace refresh fix, skipping step 4')
    * if (!ctx.schemaServerFixed) karate.abort()
    # V2 listed the catalog's namespaces in step 1, so the schema server holds that list in its
    # cache (10 minutes). Asked for a refresh, V2 must list a database and table created now:
    # a short wait for the compute's DDL, far below the cache's lifetime
    * runQuery('CREATE DATABASE IF NOT EXISTS ' + fullNew)
    * runQuery('CREATE TABLE IF NOT EXISTS ' + fullNew + '.fresh (id INT)')
    * configure retry = { count: 10, interval: 3000 }

    # V2: list the tables of the new database, with forceRefresh
    Given path v2, 'catalogs', catalogName, 'namespaces', dbNew, 'tables'
    And params fresh
    And retry until responseStatus == 200 && response.map(t => t.name).includes('fresh')
    When method get
    Then status 200
    And match response.map(t => t.name) contains 'fresh'

    # V2: list the namespaces of the catalog, with forceRefresh
    Given path v2, 'catalogs', catalogName, 'namespaces'
    And params fresh
    And retry until responseStatus == 200 && response.map(n => n.namespace).includes(dbNew)
    When method get
    Then status 200
    And match response.map(n => n.namespace) contains dbNew
