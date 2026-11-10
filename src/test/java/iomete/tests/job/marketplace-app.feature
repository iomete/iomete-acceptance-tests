@lock=job2
Feature: Marketplace apps, published, updated, deployed as a job and removed

  A marketplace app is a Spark job template the platform keeps for every domain. Publishing one
  creates nothing on the cluster: the console deploys it by reading the app's template back and
  creating a job from it, which is what this scenario does. The run is what proves the stored
  template is still a runnable application after its round trip through the marketplace, and
  that an update reaches the jobs deployed afterwards.

  The app runs SparkPi, whose one argument is the number of partitions, and the driver's own
  spark-submit line shows it, so the run shows which version of the template it was built from.
  Validation, the stored fields and permissions are iom-cluster's own logic and stay in its tests.

  Background:
    # changes platform-wide state, so it runs only where the install allows that
    * if (!platformChangesAllowed()) karate.abort()
    * url baseUrl
    * def appName = 'karate-marketplace-' + runId
    * def jobName = 'karate-marketplace-job-' + runId
    * def marketplacePath = 'api/v1/domains/' + domain + '/marketplace'

    # a job with an active run cannot be deleted, so its runs are killed first. Each step runs
    # even when one before it fails, so a stuck kill cannot leave the platform-wide app behind.
    * def clearAll =
      """
      function(jobId) {
        var steps = [
          () => { if (jobId) karate.call('classpath:iomete/helpers/job/kill-active-runs.feature', { jobId: jobId }) },
          () => karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: jobName }),
          () => karate.call('classpath:iomete/helpers/marketplace/delete-marketplace-app.feature', { name: appName })
        ];
        var errors = [];
        steps.forEach(step => { try { step() } catch (e) { errors.push(e) } });
        if (errors.length) throw errors[0];
      }
      """
    * configure afterScenario = function() { var job = karate.get('job'); clearAll(job ? job.jobId : null) }

    # a repeat of `make test-one` keeps the run id, so start without the earlier app and job
    Given path 'api/v1/domains/' + domain + '/spark/jobs'
    When method get
    Then status 200
    * def leftover = response.find(j => j.name == jobName)
    * clearAll(leftover ? leftover.id : null)

  Scenario: an updated marketplace app deploys as a job whose run uses the update, and is then removed
    * def installedPartitions = '2'
    * def updatedPartitions = '7'
    * def appRequest =
      """
      {
        name: '#(appName)',
        description: 'marketplace app for iomete-api-testing-suite, managed by tests/job/marketplace-app.feature',
        jobType: 'MANUAL',
        template: {
          image: '#(sparkImage)',
          mainApplicationFile: 'local:///opt/spark/examples/src/main/python/pi.py',
          applicationType: 'python',
          arguments: ['#(installedPartitions)']
        }
      }
      """

    Given path marketplacePath
    And request appRequest
    When method post
    Then status 201
    * def appId = response.id

    * set appRequest.template.arguments = [ '#(updatedPartitions)' ]
    Given path marketplacePath, appId
    And request appRequest
    When method put
    Then status 200

    # deploy it the console's way: read the template back and create a V2 PRIORITY job from it
    Given path marketplacePath, appId
    When method get
    Then status 200
    * def template = response.item.template

    # driver-only: SparkPi needs no executor, and one fewer pod fits a namespace quota that
    # overlapping runs keep close to full
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, jobTemplate: template, jobSingleNode: true, jobApi: 'v2', jobFlow: 'PRIORITY' })
    * def result = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: job.jobId, runJobApi: 'v2' })
    And match result.run.driverStatus == 'COMPLETED'
    * def appRunId = result.run.id

    # the driver's spark-submit line carries the argument of the template it was deployed from
    * configure retry = { count: 12, interval: 5000 }
    Given path 'api/v2/domains/' + domain + '/spark/jobs', job.jobId, 'runs', appRunId, 'logs'
    And param range = '1h'
    And retry until responseStatus == 200 && response.find(l => (l.logLine || '').includes('Pi is roughly')) != null
    When method get
    Then status 200
    And assert JSON.stringify(response).includes('pi.py ' + updatedPartitions)
    And assert !JSON.stringify(response).includes('pi.py ' + installedPartitions)

    Given path marketplacePath, appId
    When method delete
    Then status 204
