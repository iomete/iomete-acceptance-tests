@lock=job2
Feature: A scheduled job starts a run on its own

  Nothing here submits a run: it has to appear because the cron fired.

  A scheduled job keeps firing until something stops it, so the scenario pauses the schedule as
  soon as it has seen a run, and the teardown removes the job either way.

  The last run and next run are not asserted: the platform did not populate them on the
  environment this was written against.

  Background:
    * url baseUrl
    # per run, like every other fixture: two runs sharing one job pause and delete each other's
    # schedule, and neither sees a run of its own
    * def jobName = 'karate-scheduled-job-' + runId
    * def jobsPath = 'api/v1/domains/' + domain + '/spark/jobs'
    # runs count from here. A retry reuses this run's job, so the earlier attempt's runs must
    # not answer for this one; the margin covers clock skew against the platform.
    * def attemptStart = java.lang.System.currentTimeMillis() - 5000
    # every second minute, so the first run lands quickly and there is still time to pause the
    # schedule before a second one starts
    * def schedule = '*/2 * * * *'
    * def searchStart = java.lang.System.currentTimeMillis() - 60000

    # teardown: never leave a schedule firing, pass or fail
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName });
      }
      """

  Scenario: a run appears off the cron and completes
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, jobType: 'SCHEDULED', schedule: schedule })

    # the cron can fire before this scenario gets to look, so no snapshot of the runs already
    # there: a scheduler run counts when it was created after this attempt began
    * def isNewSchedulerRun = function(r){ return r.createdBy == 'Scheduler' && java.time.Instant.parse(r.createdAt).toEpochMilli() >= attemptStart }

    # three minutes tolerates a missed cron tick
    * configure retry = { count: 18, interval: 10000 }
    Given path jobsPath, job.jobId, 'runs'
    And param start = searchStart
    And retry until response.filter(isNewSchedulerRun).length > 0
    When method get
    Then status 200
    * def run = response.filter(isNewSchedulerRun)[0]
    And match run contains { jobType: 'SCHEDULED', createdBy: 'Scheduler' }

    # pause the schedule so the wait below is not racing a second run
    Given path jobsPath, job.jobId, 'suspend'
    And request { suspend: true }
    When method put
    Then assert responseStatus >= 200 && responseStatus < 300

    # cold start dominates, the example itself finishes in seconds
    * configure retry = { count: 60, interval: 10000 }
    Given path jobsPath, job.jobId, 'runs', run.id
    And retry until ['COMPLETED', 'FAILED', 'ABORTED', 'SUBMISSION_FAILED'].includes(response.driverStatus)
    When method get
    Then status 200
    And match response.driverStatus == 'COMPLETED'

    # deleting it here is the assertion that a scheduled job can be removed; the teardown only
    # steps in when the scenario failed earlier
    Given path jobsPath, job.jobId
    When method delete
    Then assert responseStatus >= 200 && responseStatus < 300
