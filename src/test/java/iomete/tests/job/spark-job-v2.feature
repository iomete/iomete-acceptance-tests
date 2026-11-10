@lock=job
Feature: Spark jobs V2, a job the console's way, run, observed, retried and killed

  The console manages Spark jobs through the V2 API and creates them on the PRIORITY flow, so
  a run is queued through the job orchestrator before it reaches Kubernetes. This follows one
  SparkPi job down that path: created through V2, run to completion, then read back
  through the endpoints the console's run page uses — the run listing, the driver pod, its logs
  and events, metrics and timeline — and finally retried and killed.

  The pod-backed reads come after the run completes: the driver pod is kept for about an hour,
  while a SparkPi run can finish between two polls. Validation, conflicts and permissions are
  iom-cluster's own logic and stay in its tests.

  Background:
    * url baseUrl
    * def jobName = 'karate-spark-v2-' + runId
    * def jobsPath = 'api/v2/domains/' + domain + '/spark/jobs'

    # a job with an active run cannot be deleted, so kill first; runs outlive the job anyway
    * configure afterScenario =
      """
      function() {
        var job = karate.get('job');
        if (job) karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: job.jobId });
        karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName });
      }
      """
    # a repeat of `make test-one` keeps the run id, so start from a job with no earlier runs
    * def cleared = call read('classpath:iomete/helpers/job/delete-job.feature') { name: '#(jobName)' }

  Scenario: a PRIORITY job runs to completion, shows its pod, logs and events, and a retry of it can be killed
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, jobApi: 'v2', jobFlow: 'PRIORITY' })

    # V2 hands the job back bare, with the bundle it was created in
    Given path jobsPath, job.jobId
    When method get
    Then status 200
    And match response contains { id: '#(job.jobId)', name: '#(jobName)', flow: 'PRIORITY', jobType: 'MANUAL' }
    And match response.template.mainApplicationFile contains 'pi.py'
    And match response.bundle == '#notnull'

    # the run is queued through the orchestrator first
    * def start = java.lang.System.currentTimeMillis() - 60000
    * def result = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId, runJobApi: 'v2' })
    And match result.run.driverStatus == 'COMPLETED'
    * def appId = result.run.id

    Given path jobsPath, job.jobId, 'runs'
    And param start = start
    When method get
    Then status 200
    And match response[*].id contains appId

    # the driver pod, as the run page's Instances tab lists it
    Given path jobsPath, job.jobId, 'runs', appId, 'instances'
    When method get
    Then status 200
    And match response[*].name contains 'job-' + appId + '-driver'

    # the driver's own output, read from the pod; SparkPi prints its estimate
    * configure retry = { count: 12, interval: 5000 }
    Given path jobsPath, job.jobId, 'runs', appId, 'logs'
    And param range = '1h'
    And retry until responseStatus == 200 && response.find(l => l.logLine.includes('Pi is roughly')) != null
    When method get
    Then status 200
    And match each response == { date: '#number', logLine: '#string' }

    Given path jobsPath, job.jobId, 'runs', appId, 'logs', 'download'
    When method get
    Then status 200
    And assert responseBytes.length > 0

    # the pod's Kubernetes events
    Given path jobsPath, job.jobId, 'runs', appId, 'events'
    When method get
    Then status 200
    And match response == '#[_ > 0]'

    Given path jobsPath, job.jobId, 'runs', appId, 'timeline'
    When method get
    Then status 200
    And match response == '#[_ > 0]'

    # metrics come from the Spark UI or history server, best effort right after a run
    Given path jobsPath, job.jobId, 'runs', appId, 'metrics'
    When method get
    Then assert responseStatus == 200 || responseStatus == 204

    Given path jobsPath, job.jobId, 'metrics'
    When method get
    Then status 200

    # a retry is a new run with the same configuration
    Given path jobsPath, job.jobId, 'runs', appId, 'retry'
    When method post
    Then status 200
    * def retriedId = response.id
    And match retriedId != appId
    And match response.jobId == job.jobId

    # and it can be killed straight away, before it reaches the cluster
    Given path jobsPath, job.jobId, 'runs', retriedId
    When method delete
    Then status 200

    * configure retry = { count: 12, interval: 5000 }
    Given path jobsPath, job.jobId, 'runs', retriedId
    And retry until responseStatus == 200 && response.driverStatus == 'ABORTED'
    When method get
    Then status 200
    And match response.driverStatus == 'ABORTED'
