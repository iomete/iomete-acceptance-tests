@lock=job2
Feature: Spark History — a completed job run is served by the history server

  One end-to-end happy path: run a Spark job, then load that run back out of the history
  server. This is what proves IometeFsHistoryProvider serves a freshly written event log.

  The platform links a run to its history entry through sparkHistoryUrl, rendered as
  spark-history/history/{sparkApplicationId}. Note the assertions go through that per
  application path, not the application listing: a new run reaches the UI through getAppUI
  probing the log directory on demand. If that read happens before the event log is fully
  written, the run stays partial until the next rescan (spark.history.fs.update.interval,
  120s on dev, peers and release), so the history wait below outlasts one rescan.

  Background:
    * url baseUrl
    * def jobName = 'karate-spark-history-probe-' + runId
    * def jobsPath = 'api/v1/domains/' + domain + '/spark/jobs'

  Scenario: a completed job run is visible in the Spark History UI
    # set before the create, so a job left by a failing create is still removed. A delete is
    # refused while a run is active, so kill its runs first.
    * configure afterScenario = function(){ var job = karate.get('job'); if (job) karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: job.jobId }); karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName }) }
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName })

    Given path jobsPath, job.jobId, 'runs'
    And request {}
    When method post
    Then status 200
    * def runId = response.id

    # cold start dominates — the example itself finishes in seconds
    * configure retry = { count: 60, interval: 10000 }
    Given path jobsPath, job.jobId, 'runs', runId
    And retry until ['COMPLETED', 'FAILED', 'ABORTED', 'SUBMISSION_FAILED'].includes(response.driverStatus)
    When method get
    Then status 200
    And match response.driverStatus == 'COMPLETED'

    # the application id is attached once the driver has reported in
    * configure retry = { count: 12, interval: 5000 }
    Given path jobsPath, job.jobId, 'runs', runId
    And retry until response.sparkHistoryUrl != null && response.sparkHistoryUrl != ''
    When method get
    Then status 200
    * def historyUrl = response.sparkHistoryUrl
    * def sparkAppId = historyUrl.substring(historyUrl.lastIndexOf('/') + 1)
    And match sparkAppId == '#regex spark-[0-9a-f]+'

    # The REST base is derived from sparkHistoryUrl: a remote-plane run links to
    # spark-history/data-plane/{plane}/..., routed to that plane's own history server —
    # a hardcoded local path asks the control plane for an event log it does not have.
    * def apiBase = historyUrl.replace('/history/' + sparkAppId, '/api/v1/applications/' + sparkAppId)

    # the history server rebuilds this run's UI from the event log it just wrote; a partial
    # read is only replaced on the next rescan (120s), so wait ~200s
    * configure retry = { count: 20, interval: 10000 }
    Given url baseUrl + '/' + apiBase + '/jobs'
    And retry until responseStatus == 200 && response.length > 0
    When method get
    Then status 200
    * url baseUrl
    And match each response contains { jobId: '#number', status: 'SUCCEEDED' }

    # and the page the console links to renders for that application
    Given url baseUrl + '/' + historyUrl + '/jobs/'
    When method get
    Then status 200
    And match response contains sparkAppId
    And match response contains 'Spark Jobs'

    # the run and its event log outlive the job definition, so the history assertions above
    # stay valid after this
    Given url baseUrl
    And path jobsPath, job.jobId
    When method delete
    Then assert responseStatus >= 200 && responseStatus < 300
