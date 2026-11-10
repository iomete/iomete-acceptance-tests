@ignore
Feature: Post this run's Event Stream events and wait for them — invoked once per run via callSingle.
  Ingestion is asynchronous, so posting from each scenario meant each one waiting out a loader
  cycle of its own. Everything is posted here and waited for once.
  Returns: database, computeName, marker.

  Scenario: post every event, then wait until the last one is queryable
    * def stream = karate.callSingle('classpath:iomete/tests/event-stream/setup/event-stream.feature', { domain: domain })
    * def types = karate.callSingle('classpath:iomete/tests/event-stream/setup/types-db.feature', { domain: domain })
    * def database = types.database
    * def computeName = types.computeName
    * def ingestPath = stream.ingestPath

    # per attempt, so a retry of the same run cannot count the first attempt's rows
    * def marker = 'es-' + runId + '-' + java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36)

    * def send =
      """
      function(table, events) {
        var res = karate.call('classpath:iomete/helpers/event-stream/ingest.feature',
                              { ingestPath: ingestPath, table: table, events: events });
        if (res.code != 200) karate.fail('ingest into ' + table + ' answered ' + res.code + ': ' + res.body);
      }
      """

    * def primitives = database + '.primitives'
    * send(primitives, [{ flag: true, i: 42, l: 9007199254740991, f: 1.5, d: 2.25, s: marker, small_dec: 1212.34345, dt: '2024-01-15', ts: '2024-01-15T10:30:00Z' }])

    # The optional columns left out of the event entirely.
    * def nullable = database + '.nullable'
    * send(nullable, [{ id: 1 }])

    # One row carrying every complex shape.
    * def complex = database + '.complex'
    * send(complex, [{ id: 10, addr: { street: 'Nizami 1', city: 'Baku', zip: 'AZ1000' }, tags: ['alpha', 'beta'], counts: { reads: 7, writes: 3 }, items: [{ name: 'widget', qty: 2 }, { name: 'gadget', qty: 5 }], deep: { outer: { inner: 'bottom' } } }])

    # A thousand events in one POST.
    * def batch = database + '.batch'
    * def build =
      """
      function(count, label) {
        var out = [];
        for (var i = 0; i < count; i++) out.push({ seq: i, label: label });
        return out;
      }
      """
    * send(batch, build(1000, marker))

    # The loader commits tables in separate cycles, in no fixed order, so wait until every table
    # has its rows. Checked every 30s, up to 10 times.
    * def waitForRows =
      """
      function() {
        var pending = [
          { table: 'primitives', sql: "SELECT count(*) FROM " + primitives + " WHERE s = '" + marker + "'", want: 1 },
          { table: 'nullable', sql: "SELECT count(*) FROM " + nullable + " WHERE id = 1", want: 1 },
          { table: 'complex', sql: "SELECT count(*) FROM " + complex + " WHERE id = 10", want: 1 },
          { table: 'batch', sql: "SELECT count(*) FROM " + batch + " WHERE label = '" + marker + "'", want: 1000 }
        ];
        for (var i = 0; i < 10; i++) {
          java.lang.Thread.sleep(30000);
          pending = pending.filter(function(c) {
            var r = karate.call('classpath:iomete/helpers/query/run-query-v2.feature',
                                { domain: domain, computeName: computeName, statement: c.sql }).result;
            var n = (r && r.values && r.values.length) ? r.values[0] : 0;
            return n < c.want;
          });
          if (pending.length == 0) return;
        }
        karate.fail('rows still missing after 5 minutes in: ' + pending.map(function(c) { return c.table; }).join(', '));
      }
      """
    * waitForRows()
