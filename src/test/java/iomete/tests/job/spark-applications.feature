@lock=job
Feature: Spark applications, a job run is listed with the status its driver reported

  The applications view lists Spark job runs across jobs. The platform writes a run's row as
  ENQUEUED when it is submitted; only the driver's real Kubernetes events move it on, so a run
  listed as COMPLETED is what proves the view follows the live application. Each listing is
  filtered to this run's job, tag and time window, so other runs on the target cannot answer
  for it.

  Filtering rules, permissions and tag-format validation are iom-cluster's own logic and stay
  in its tests.

  Background:
    * url baseUrl
    * def jobName = 'karate-spark-apps-' + runId
    * def tagKey = 'karate-run'
    # the run id repeats across `make test-one`, the CI retry and the other image leg, and runs
    # outlive their job, so the tag value is unique to this execution
    * def tagValue = runId + '-' + java.lang.System.currentTimeMillis()
    * def tag = { key: '#(tagKey)', value: '#(tagValue)' }
    * def appsV1 = 'api/v1/domains/' + domain + '/spark/applications'
    * def appsV2 = 'api/v2/domains/' + domain + '/spark/applications'

    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName });
      }
      """
    # a repeat of `make test-one` keeps the run id, so start from a job with no earlier runs
    * def cleared = call read('classpath:iomete/helpers/job/delete-job.feature') { name: '#(jobName)' }

  Scenario: a completed run shows up in the v1 and v2 listings, its tags and the submission timeline
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName })

    # the window opens just before the submit: listings filter on the run's creation time, in ms
    * def start = java.lang.System.currentTimeMillis() - 60000

    * def result = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId, runResourceTags: [tag] })
    And match result.run.driverStatus == 'COMPLETED'
    * def appId = result.run.id

    * def end = java.lang.System.currentTimeMillis() + 60000
    * def window = { start: '#(start)', end: '#(end)' }

    # status updates arrive from the driver's events, so give the listing a moment to catch up
    * configure retry = { count: 12, interval: 5000 }
    Given path appsV2
    And params karate.merge(window, { jobId: job.jobId })
    And retry until response.length == 1 && response[0].driverStatus == 'COMPLETED'
    When method get
    Then status 200
    And match response[0] contains { id: '#(appId)', jobId: '#(job.jobId)', driverStatus: 'COMPLETED', dataPlane: '#string' }
    And match response[0].resourceTags contains tag

    # the run's own tag picks it out of every job's runs
    Given path appsV2
    And params karate.merge(window, { tag: tagKey + ':' + tagValue })
    When method get
    Then status 200
    And match response[*].id == ['#(appId)']

    Given path appsV2, 'tags'
    And params window
    When method get
    Then status 200
    And match response contains tag

    # one submission in the window, counted under the status the driver ended on
    * def completedIn = function(buckets){ return buckets.reduce((sum, b) => sum + ((b.statuses || {}).COMPLETED || 0), 0) }
    Given path appsV2, 'timeline'
    And params karate.merge(window, { jobId: job.jobId })
    When method get
    Then status 200
    And match completedIn(response) == 1

    # the v1 routes serve the same rows behind the domain-level permission check
    Given path appsV1
    And params karate.merge(window, { jobId: job.jobId })
    When method get
    Then status 200
    And match response[*].id == ['#(appId)']

    Given path appsV1, 'timeline'
    And params karate.merge(window, { jobId: job.jobId })
    When method get
    Then status 200
    And match completedIn(response) == 1
