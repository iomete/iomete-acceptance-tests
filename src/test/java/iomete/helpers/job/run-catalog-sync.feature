@ignore
Feature: Run the catalog-sync job once and wait for it to finish (plumbing).
  The data catalog only learns about tables through this job, which is scheduled hourly
  by default, so a scenario that needs a fresh table in the catalog runs it itself:
    karate.call('classpath:iomete/helpers/job/run-catalog-sync.feature', { name: 'karate-catalog-sync-' + runId })

  Builds a manual job from the marketplace's catalog-sync template, the way the console does.
  The caller deletes it afterwards (helpers/job/delete-job.feature).

  Scenario: create the job from the marketplace template, run it and wait for COMPLETED
    * def marketplacePath = 'api/v1/domains/' + domain + '/marketplace'

    Given url baseUrl
    And path marketplacePath
    When method get
    Then status 200
    * def app = response.items.find(a => a.name == 'catalog-sync')
    * if (app == null) karate.fail('the catalog-sync marketplace template is missing in domain ' + domain)

    Given path marketplacePath, app.id
    When method get
    Then status 200
    * def template = response.item.template
    And match template.mainClass == 'com.iomete.catalogsync.App'

    # a Quarkus app inside the Spark driver: more than karate-xs holds, and no executors. The
    # run limit sits inside the wait below, so a run this scenario gave up on is already stopped.
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: name, jobTemplate: template, jobDriverType: 'karate-driver', jobSingleNode: true, jobMaxDurationSeconds: '900' })

    # another sync writing the same rows at once (the hourly one, or an overlapping run's) can
    # fail this one, and the sync is safe to repeat, so a failed run gets one more go. 96 polls
    # outlast the 900s run limit.
    * def runSync = function(){ return karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId, waitCount: 96 }).run }
    * def run = runSync()
    * if (run.driverStatus == 'FAILED') run = runSync()
    * match run.driverStatus == 'COMPLETED'
