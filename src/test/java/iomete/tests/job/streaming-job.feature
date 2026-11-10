@lock=job
Feature: Streaming jobs, a job started, running, observed and stopped the console's way

  A streaming job runs until it is stopped, so the questions worth asking the real platform are
  whether it gets to RUNNING, whether the running driver can be seen (its pod, its output, its
  events) and whether a stop actually ends the driver. The job runs the image's DStream word count on a
  directory nothing writes to (and that need not exist): it needs no source, never finishes on
  its own, and prints a batch header every second. Not /tmp itself, where Spark's own temp files
  would be read as input.

  It uses the run's configured Spark image (IOMETE_SPARK_IMAGE), like the other job tests.

  Conflict and validation rules (one active application per job, no delete while running, the
  log range) are iom-cluster's own logic and stay in its tests.

  Background:
    * url baseUrl
    * def jobName = 'karate-streaming-' + runId
    * def streamingPath = 'api/v2/domains/' + domain + '/spark/streaming/jobs'
    * def endedStates = ['FAILED', 'ABORTED', 'SUBMISSION_FAILED', 'COMPLETED']

    # a streaming job never stops on its own, so teardown always stops and deletes it
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/job/delete-streaming-job.feature', { name: jobName });
      }
      """
    * def cleared = call read('classpath:iomete/helpers/job/delete-streaming-job.feature') { name: '#(jobName)' }

  Scenario: a streaming job reaches RUNNING, shows its driver, output and events, and a stop ends the driver
    # the console creates streaming jobs on the LEGACY flow; use the run's configured image
    * def image = sparkImage
    * def template = { image: '#(image)', imagePullSecrets: [], applicationType: 'python', mainApplicationFile: 'local:///opt/spark/examples/src/main/python/streaming/hdfs_wordcount.py', arguments: ['/tmp/karate-streaming-input'] }
    * def job = karate.call('classpath:iomete/helpers/job/create-job.feature', { name: jobName, jobApi: 'streaming', jobFlow: 'LEGACY', jobTemplate: template })

    Given path streamingPath, job.jobId, 'start'
    And request {}
    When method post
    Then status 200
    * def appId = response.id

    # cold start dominates; stop early if the application ends instead of running
    * configure retry = { count: 60, interval: 10000 }
    Given path streamingPath, job.jobId, 'applications', appId
    And retry until response.driverStatus == 'RUNNING' || endedStates.includes(response.driverStatus)
    When method get
    Then status 200
    * if (response.driverStatus != 'RUNNING') karate.log('application did not reach RUNNING:', response)
    And match response.driverStatus == 'RUNNING'

    # the running driver, as the console's application page shows it
    Given path streamingPath, job.jobId, 'applications', appId, 'instances'
    When method get
    Then status 200
    And match response[*].name contains 'job-' + appId + '-driver'

    # a batch header prints every second once running, but the first can take over a minute after RUNNING
    * configure retry = { count: 36, interval: 5000 }
    Given path streamingPath, job.jobId, 'applications', appId, 'logs'
    And param range = '15m'
    And retry until responseStatus == 200 && response.find(l => (l.logLine || '').includes('Time:')) != null
    When method get
    Then status 200

    Given path streamingPath, job.jobId, 'applications', appId, 'events'
    When method get
    Then status 200
    # the kubelet's own record of the pod
    And match response[*].reason contains any ['Scheduled', 'Started']

    # a stop has to end the running driver
    Given path streamingPath, job.jobId, 'stop'
    When method post
    Then status 200

    * configure retry = { count: 24, interval: 5000 }
    Given path streamingPath, job.jobId, 'applications', appId, 'instances'
    # the platform keeps listing a stopped driver, so what has to change is its state
    And retry until responseStatus == 200 && (response.find(p => p.name == 'job-' + appId + '-driver') || {}).status != 'Running'
    When method get
    Then status 200
    * karate.log('driver after stop:', response.find(p => p.name == 'job-' + appId + '-driver'))
