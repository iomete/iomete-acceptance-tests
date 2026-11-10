Feature: Delete every karate-owned event stream in the domain (manual teardown).

  The suite's shared stream (karate-es) is never deleted automatically, the same way the computes
  are left running. A killed run's lifecycle stream (karate-es-lc-{runId}) is removed by
  make cleanup-run-computes for that run id. This removes the shared stream and every karate-es-*
  stream by hand, an overlapping run's lifecycle stream included: each replica holds 2 CPU / 4 GiB
  of the namespace quota, so a stale or wedged one is worth clearing.

  Targeted by path and never scanned, the same way helpers/compute/stop-domain-computes.feature
  is. Run it with:
    make test-one FEATURE=src/test/java/iomete/helpers/event-stream/delete-all-karate-streams.feature

  Scenario: find every karate-* stream and delete it
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/event-streams'
    And params { size: 200 }
    When method get
    Then status 200

    * def mine = response.items.filter(x => x.name == 'karate-es' || x.name.startsWith('karate-es-'))
    * print 'found', mine.length, 'karate event stream(s)'

    * def removeOne =
      """
      function(stream) {
        var res = karate.call('classpath:iomete/helpers/event-stream/delete-stream.feature',
                              { streamId: stream.id });
        karate.log(stream.name, res.deleted ? 'deleted' : 'FAILED (status ' + res.code + ')');
        return res.deleted;
      }
      """
    * def results = mine.map(removeOne)
    * def failed = results.filter(ok => !ok).length
    * match failed == 0
