Feature: Stop every streaming job in the suite's domains, so earlier runs' leftovers release capacity.

  A streaming job never ends on its own, and a cancelled run leaves its job running until
  `make cleanup` deletes it or this stops it. This stops the application of every streaming job in the
  domain, whichever run created it. It stops rather than deletes, so a run still using its
  job can find it and clean it up itself.

  Run it with `make stop-streaming-jobs`. It is targeted by path and never scanned, since
  helpers/ sits outside iomete/tests.

  @setup
  Scenario: the suite's domains
    # the fixed karate domain of older platforms, plus one per run from 4.0.2, killed runs' included
    Given url baseUrl
    And path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domains = response.filter(d => d.id == domain || d.id == 'karate' || d.id.startsWith('karate-')).map(d => ({ domain: d.id }))

  Scenario Outline: stop every streaming job in domain <domain>
    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/spark/streaming/jobs'
    And params { page: 0, size: 1000 }
    When method get
    # a target without the streaming API has no streaming jobs to stop
    * if (responseStatus == 404) { java.lang.System.out.println('no streaming jobs API in domain ' + domain + ', nothing to stop'); karate.abort() }
    Then status 200
    * def jobs = response.items
    * def total = response.total

    * def stopAll =
      """
      function(jobs) {
        var failed = [];
        for (var i = 0; i < jobs.length; i++) {
          try {
            karate.call('classpath:iomete/helpers/job/stop-streaming-job.feature', { jobId: jobs[i].id });
          } catch (e) {
            failed.push(jobs[i].name + ': ' + e);
          }
        }
        return failed;
      }
      """
    * def failed = stopAll(jobs)

    # straight to stdout: `print` only reaches the HTML report
    * eval java.lang.System.out.println('stopped the streaming jobs in domain ' + domain + ' (' + jobs.length + ' listed): ' + jobs.map(j => j.name).join(', '))

    * match failed == []
    # one page is plenty for a test domain; fail if some were left unstopped
    * match total == jobs.length

    Examples:
      | karate.setup().domains |
