@lock=api
Feature: SQL schema parity — the table details match where they already do

  The table details fields that already match V1: name, namespace, column names, field
  nullability, partitions and the provider, and the table's snapshots with their commit times.
  The admin V2 route and the V1 domain route (which forwards to V2) must answer exactly what the
  domain V2 route answers. Types, column comments and views are compared in types-and-views.

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
    * def v2Admin = ctx.v2Admin
    * def v1Forwards = ctx.v1Forwards
    * def catalogName = ctx.catalogName
    * def namespace = ctx.namespace
    * def fresh = ctx.fresh

  Scenario: the table details match V1, and every V2 route answers the same body

    # ===== 1. Table details: V1 vs V2 =====
    # the table: what already matches V1

    # V1 (native): describe employees in the seeded namespace
    Given path v1Native, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees'
    When method get
    Then status 200
    * def v1Table = response
    # the table is seeded by this run; V2 reads through the schema server's cache (V1 reads
    # live, LKH-1092), so ask it to look again and give it a moment to see the new table
    * configure retry = { count: 10, interval: 3000 }

    # V2: describe employees in the seeded namespace
    Given path v2, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees'
    And params fresh
    And retry until responseStatus == 200
    When method get
    Then status 200
    * def v2Table = response
    And match v2Table.name == v1Table.name
    And match v2Table.namespace == v1Table.namespace
    And match v2Table.columns.map(c => c.name) == v1Table.columns.map(c => c.name)
    And match v2Table.fields.map(f => f.name + ':' + f.nullable) == v1Table.fields.map(f => f.name + ':' + f.nullable)
    And match v2Table.partitions == v1Table.partitions
    And match v2Table.isPartitioned == v1Table.isPartitioned
    And match v2Table.provider.toLowerCase() == v1Table.provider.toLowerCase()

    # ===== 2. Same body on every V2 route: admin and forwarded V1 =====
    # the admin V2 route and the V1 domain route (forwarded to V2) answer what V2 answers

    # V2 admin: describe employees in the seeded namespace
    Given path v2Admin, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees'
    And retry until responseStatus == 200
    When method get
    Then status 200
    And match response == v2Table

    # V1 (the route customers call): describe employees in the seeded namespace. While it forwards
    # it answers exactly what V2 does; otherwise V1's own code, exactly what V1 native does
    Given path v1Forwarded, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees'
    And retry until responseStatus == 200
    When method get
    Then status 200
    * def expectedV1 = v1Forwards ? v2Table : v1Table
    And match response == expectedV1

    # ===== 3. Snapshots: the same snapshots, committed at the same time, on V1 and V2 =====
    # V2 writes `committed_at` like V1 from 4.0.2
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the V2 schema fixes these checks compare, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()
    # V1 and V2 write `committed_at` the same way (millisecond ISO-8601, `+00:00`)
    * def snapshotKeys = function(rows){ return rows.map(r => r.snapshot_id + ' ' + r.committed_at).sort() }

    # V1 (native): the snapshots and refs of employees
    Given path v1Native, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees', 'snapshots-and-refs'
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    * def v1Snapshots = response

    # V2: the snapshots and refs of employees
    # V1 reads live; V2 may still hold an older list (a retry under the same run id reseeds the
    # table, adding a snapshot), so ask it to look again and give it a moment
    Given path v2, 'catalogs', catalogName, 'namespaces', namespace, 'tables', 'employees', 'snapshots-and-refs'
    And params fresh
    And retry until responseStatus == 200 && snapshotKeys(response).join() == snapshotKeys(v1Snapshots).join()
    When method get
    Then status 200
    And match snapshotKeys(response) == snapshotKeys(v1Snapshots)
