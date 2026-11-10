@ignore
Feature: Kill every run of a job that has not finished (plumbing).
  Teardown helper, safe to call when the job or its runs are already gone:
    karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: id })

  A job is refused deletion while one of its runs is active, so a teardown calls this first.
  A kill takes effect asynchronously, so this waits until no run of the job is active.

  Scenario: kill the job's non-terminal runs
    * def runsPath = 'api/v2/domains/' + domain + '/spark/jobs/' + jobId + '/runs'
    * def finished = ['COMPLETED', 'FAILED', 'ABORTED', 'SUBMISSION_FAILED']
    # an ABORTING run refuses a second kill but still holds up the delete, so it is waited out
    * def unkillable = finished.concat(['ABORTING'])

    Given url baseUrl
    And path runsPath
    And param start = java.lang.System.currentTimeMillis() - 24 * 3600 * 1000
    When method get
    * if (responseStatus != 200) karate.abort()
    * def active = response.filter(r => !finished.includes(r.driverStatus))
    * def killable = active.filter(r => !unkillable.includes(r.driverStatus))
    * def kill = function(run){ karate.call('classpath:iomete/helpers/job/kill-run.feature', { runsPath: runsPath, runId: run.id }) }
    * karate.forEach(killable, kill)
    * if (active.length == 0) karate.abort()

    * configure retry = { count: 24, interval: 5000 }
    Given url baseUrl
    And path runsPath
    And param start = java.lang.System.currentTimeMillis() - 24 * 3600 * 1000
    And retry until responseStatus == 200 && response.filter(r => !finished.includes(r.driverStatus)).length == 0
    When method get
    Then status 200
