Feature: Stop every compute in the suite's domains, the suite teardown.

  The suite's computes are shared and long-lived: create-compute.feature gets-or-creates
  them and a finished run leaves them RUNNING, with only the 1800s idle timeout to stop
  them. A run that fails or is cancelled leaves them running too, and four warm computes
  pin enough of the spark node pool that the next run's executors cannot be scheduled.
  This stops them explicitly instead of waiting the timeout out.

  Stops rather than deletes, because STOPPED is the state create-compute reuses via 409,
  so the next run still skips the create and pays only the warm-up.

  Run it with `make stop-computes`. It is targeted by path and never scanned, since
  helpers/ sits outside iomete/tests.

  @setup
  Scenario: the suite's domains
    # the fixed karate domain of older platforms, plus one per run from 4.0.2, killed runs' included
    Given url baseUrl
    And path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domains = response.filter(d => d.id == domain || d.id == 'karate' || d.id.startsWith('karate-')).map(d => ({ domain: d.id }))

  Scenario Outline: stop every compute in domain <domain>
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    Given url baseUrl
    And path computePath
    And params { page: 0, size: 1000 }
    When method get
    Then status 200
    * def computes = response.items
    # the list has no total, so a full page means some computes may be unseen
    * assert computes.length < 1000

    # Everything in this domain belongs to the suite, so there is no name list to keep in
    # sync with the setup features that own those names.
    * def stopAll =
      """
      function(computes) {
        var stopped = [];
        var failed = [];
        for (var i = 0; i < computes.length; i++) {
          var compute = computes[i];
          try {
            karate.call('classpath:iomete/helpers/compute/cleanup.feature', { computeId: compute.id });
            stopped.push(compute.name);
          } catch (e) {
            failed.push(compute.name + ': ' + e);
          }
        }
        return { stopped: stopped, failed: failed };
      }
      """
    * def result = stopAll(computes)

    # straight to stdout: `print` only reaches the HTML report, which this run does not upload
    * eval java.lang.System.out.println('stopped ' + result.stopped.length + ' of ' + computes.length + ' compute(s) in domain ' + domain + ': ' + result.stopped.join(', '))

    # A compute left running is what this exists to prevent, so fail rather than log.
    * match result.failed == []

    Examples:
      | karate.setup().domains |
