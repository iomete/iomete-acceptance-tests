@lock=stream
Feature: Event Stream — a value sent over HTTP reaches the Iceberg table unchanged

  Covers the chain, not the type conversions: gateway route, proxy, papyrus writing Avro, the
  loader committing Parquet, and the row readable over SQL. Conversions belong in papyrus's and
  the loader's own unit tests; what no single service can prove is the round trip.

  setup/seed-events.feature posts the events once per run and waits for the loader; the scenarios
  only read. Posting per scenario meant waiting out a loader cycle for each one.

  Background:
    # external streams need the local plane — self-skip where there is none (see has-local-plane.feature)
    * def planes = karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature')
    * if (!planes.hasLocalPlane) karate.log('external event streams need a local (default) data plane and this target has none — skipping')
    * if (!planes.hasLocalPlane) karate.abort()

    * def seeded = karate.callSingle('classpath:iomete/tests/event-stream/setup/seed-events.feature', { domain: domain })
    * def db = seeded.database
    * def computeName = seeded.computeName
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }

  Scenario: primitive and date/time values survive the round trip
    * def row = runQuery("SELECT flag, i, l, f, d, s, small_dec, dt, ts FROM " + db + ".primitives WHERE s = '" + seeded.marker + "'")
    * def v = row.values
    * match v[0] == true
    * match v[1] == 42
    * match v[2] == 9007199254740991
    * match v[3] == 1.5
    * match v[4] == 2.25
    * match v[5] == seeded.marker
    * match v[6] == 1212.34345
    # Numbers, not text, over this API: a date is days since the epoch (19737 = 2024-01-15) and
    # a timestamp is microseconds.
    * match v[7] == 19737
    * match v[8] == 1705314600000000

  Scenario: an omitted field lands as NULL
    * def row = runQuery("SELECT id, maybe_s, maybe_i FROM " + db + ".nullable WHERE id = 1")
    * match row.values == [1, null, null]

  Scenario: structs, lists and maps survive the round trip, including nested ones
    # One row carrying every nested shape: struct, list, map, list of structs, struct in struct.
    * def row = runQuery("SELECT addr.street, addr.city, size(tags), tags[0], counts['reads'], size(items), items[0].name, items[0].qty, deep.outer.inner FROM " + db + ".complex WHERE id = 10")
    * def v = row.values
    * match v[0] == 'Nizami 1'
    * match v[1] == 'Baku'
    * match v[2] == 2
    * match v[3] == 'alpha'
    * match v[4] == 7
    * match v[5] == 2
    * match v[6] == 'widget'
    * match v[7] == 2
    * match v[8] == 'bottom'
