@lock=stream
Feature: Event Stream — a column added to a live table is picked up

  Crosses three services: the catalog serves the new schema, papyrus caches it for 60s, and the
  loader skips any Iceberg column the Avro record has no field for. Owns its table, since altering
  a shared one would change what the other features assert against.

  Background:
    # external streams need the local plane — self-skip where there is none (see has-local-plane.feature)
    * def planes = karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature')
    * if (!planes.hasLocalPlane) karate.log('external event streams need a local (default) data plane and this target has none — skipping')
    * if (!planes.hasLocalPlane) karate.abort()

    * def stream = karate.callSingle('classpath:iomete/tests/event-stream/setup/event-stream.feature', { domain: domain })
    * def types = karate.callSingle('classpath:iomete/tests/event-stream/setup/types-db.feature', { domain: domain })
    * def db = types.database
    * def computeName = types.computeName
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }
    * def send =
      """
      function(table, events) {
        var res = karate.call('classpath:iomete/helpers/event-stream/ingest.feature',
                              { ingestPath: stream.ingestPath, table: table, events: events });
        if (res.code != 200) karate.fail('ingest into ' + table + ' answered ' + res.code + ': ' + res.body);
      }
      """
    # The loader commits on its own schedule, so the row itself is the only thing to wait on.
    * def waitForRow =
      """
      function(sql) {
        for (var i = 0; i < 10; i++) {
          java.lang.Thread.sleep(30000);
          var r = runQuery(sql);
          if (r && r.values && r.values.length > 0) return r;
        }
        karate.fail('no row arrived for: ' + sql);
      }
      """

  Scenario: an event sent before the column existed keeps its row, and one sent after fills it
    # Dropped even on failure, so no half-altered table is left behind.
    * def table = db + '.evolving_' + runId
    * configure afterScenario = function(){ runQuery('DROP TABLE IF EXISTS ' + table) }
    * runQuery('CREATE TABLE ' + table + ' (id int, name string) USING iceberg')

    * send(table, [{ id: 1, name: 'before' }])
    * def first = waitForRow("SELECT name FROM " + table + " WHERE id = 1")
    * match first.values[0] == 'before'

    * runQuery('ALTER TABLE ' + table + ' ADD COLUMN extra string')

    # Sent while papyrus still has the old schema cached: it must still land, since losing the
    # event would be worse than leaving the new column null on it.
    * send(table, [{ id: 2, name: 'during' }])

    # Past the 60s cache TTL, so the new schema is in use.
    * eval java.lang.Thread.sleep(70000)
    * send(table, [{ id: 3, name: 'after', extra: 'filled' }])
    * def third = waitForRow("SELECT name, extra FROM " + table + " WHERE id = 3")
    * match third.values[0] == 'after'
    * match third.values[1] == 'filled'

    # Both earlier rows are still there, with the new column null on them.
    * def second = runQuery("SELECT name, extra FROM " + table + " WHERE id = 2")
    * match second.values == ['during', null]
    * def oldest = runQuery("SELECT name, extra FROM " + table + " WHERE id = 1")
    * match oldest.values == ['before', null]
