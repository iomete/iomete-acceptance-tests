@lock=job2
Feature: SDK jobs, a job managed the way a customer's script does it

  Customers drive Spark jobs from code through the SDK API (`api/v2/domains/{domain}/sdk/spark/jobs`),
  which the console never calls: look the job up by name, run it with per-run overrides, poll the
  run until it ends, read its logs, and cancel a run they no longer want. An SDK job is an ordinary
  Spark job behind a different response shape, so the console's V2 run endpoints read the same run.

  Validation, permissions and the response mapping are iom-cluster's own logic and stay in its tests.

  Background:
    * url baseUrl
    * def jobName = 'karate-spark-sdk-' + runId
    * def sdkPath = 'api/v2/domains/' + domain + '/sdk/spark/jobs'

    # a job with an active run cannot be deleted, so kill first
    * configure afterScenario =
      """
      function() {
        var job = karate.get('job');
        if (job) karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: job.jobId });
        karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName });
      }
      """
    # a repeat of `make test-one` keeps the run id, so start from no job of this name; a job left
    # with an active run refuses deletion, so its runs are killed first
    Given path sdkPath, 'name', jobName
    When method get
    * if (responseStatus == 200) karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: response.id })
    * def cleared = call read('classpath:iomete/helpers/job/delete-job.feature') { name: '#(jobName)' }

  Scenario: an SDK job is found by name, runs with its overrides, logs its output, and a running run is cancelled
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, jobApi: 'sdk' })

    # what a script does first: find its job by name
    Given path sdkPath, 'name', jobName
    When method get
    Then status 200
    * def jobId = response.id

    # a run with its own arguments, polled until it ends, as the SDK does
    * def overrides = { arguments: ['3'] }
    * def result = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: jobId, runJobApi: 'sdk', runOverrides: overrides })
    * if (result.run.driverStatus != 'COMPLETED') karate.log('run did not complete:', result.run)
    And match result.run.driverStatus == 'COMPLETED'
    * def appId = result.run.id

    * configure retry = { count: 12, interval: 5000 }
    Given path sdkPath, jobId, 'runs', appId, 'logs'
    And param range = '1h'
    And retry until responseStatus == 200 && JSON.stringify(response).includes('Pi is roughly')
    When method get
    Then status 200
    # the driver's own spark-submit line shows the run's argument, not the job's default of 2
    And assert JSON.stringify(response).includes('pi.py 3')

    # a run the script no longer wants is cancelled while it runs: a long workload keeps the
    # driver up, and the cancel has to end it. The SDK lists no pods, so the regular V2
    # run (the same run) is asked.
    * def podsPath = 'api/v2/domains/' + domain + '/spark/jobs/' + jobId + '/runs'
    Given path sdkPath, jobId, 'runs'
    And request { arguments: ['3000'] }
    When method post
    Then status 200
    * def cancelledId = response.id
    # the driver pod is job-{runId}-driver on current platforms and {runId}-driver on older ones,
    # both ending in {runId}-driver (as compute-runtime.feature matches its driver)
    * def isDriver = function(p){ return p.name.endsWith(cancelledId + '-driver') }

    * configure retry = { count: 60, interval: 10000 }
    Given path podsPath, cancelledId, 'instances'
    And retry until responseStatus == 200 && response.find(p => isDriver(p) && p.status == 'Running') != null
    When method get
    Then status 200

    Given path sdkPath, jobId, 'runs', cancelledId
    When method delete
    Then status 200

    * configure retry = { count: 24, interval: 5000 }
    Given path podsPath, cancelledId, 'instances'
    # the platform keeps listing a killed driver, so what has to change is its state
    And retry until responseStatus == 404 || (responseStatus == 200 && (response.find(isDriver) || {}).status != 'Running')
    When method get
    * karate.log('driver after cancel:', responseStatus, responseStatus == 200 ? response.find(isDriver) : response)
