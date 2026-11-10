@lock=stream
Feature: Event Stream — a batch of events arrives whole

  One POST carries many events and the loader commits them in batches of its own. Guards against
  rows going missing in between, which no unit test on either side can see. Shares
  setup/seed-events.feature with ingest-data-types.feature — callSingle caches it, so there is no
  second wait for the loader.

  Background:
    # external streams need the local plane — self-skip where there is none (see has-local-plane.feature)
    * def planes = karate.callSingle('classpath:iomete/helpers/dataplane/has-local-plane.feature')
    * if (!planes.hasLocalPlane) karate.log('external event streams need a local (default) data plane and this target has none — skipping')
    * if (!planes.hasLocalPlane) karate.abort()

    * def seeded = karate.callSingle('classpath:iomete/tests/event-stream/setup/seed-events.feature', { domain: domain })
    * def db = seeded.database
    * def computeName = seeded.computeName
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }

  Scenario: every event in a batch of 1000 arrives, exactly once
    * def total = runQuery("SELECT count(*) FROM " + db + ".batch WHERE label = '" + seeded.marker + "'")
    * match total.values[0] == 1000
    # Distinct as well as the count: a retry committing a file twice would pass the count alone.
    * def distinct = runQuery("SELECT count(DISTINCT seq) FROM " + db + ".batch WHERE label = '" + seeded.marker + "'")
    * match distinct.values[0] == 1000
