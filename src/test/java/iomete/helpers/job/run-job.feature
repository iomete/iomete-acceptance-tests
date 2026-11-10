@ignore
Feature: Start one run of a job and wait until it ends (plumbing).
  Returns the run as run, without asserting on its outcome, so the caller decides:
    def result = karate.call('classpath:iomete/helpers/job/run-job.feature', { jobId: id, waitCount: 96 })
  waitCount is the number of 10s polls before giving up (default 60). runResourceTags tags this
  run only ([{key, value}]). runJobApi: 'v2' goes through the V2 API the console uses, 'sdk'
  through the V2 SDK API (default v1). runOverrides is the run's body (arguments, envVars,
  sparkConf...; default none). Inputs carry a run prefix because karate.get also sees the
  caller's variables.

  Scenario: start a run and poll it until it reaches a terminal status
    * def runJobApi = karate.get('runJobApi', 'v1')
    * def jobsPath = runJobApi == 'sdk' ? 'api/v2/domains/' + domain + '/sdk/spark/jobs' : 'api/' + runJobApi + '/domains/' + domain + '/spark/jobs'
    * def waitCount = karate.get('waitCount', 60)
    * def runResourceTags = karate.get('runResourceTags', null)
    * def runRequest = karate.merge(karate.get('runOverrides', {}), runResourceTags ? { resourceTags: runResourceTags } : {})

    Given url baseUrl
    And path jobsPath, jobId, 'runs'
    And request runRequest
    When method post
    Then status 200
    * def startedId = response.id

    * def retryConfig = { count: '#(waitCount)', interval: 10000 }
    * configure retry = retryConfig
    Given path jobsPath, jobId, 'runs', startedId
    # a PRIORITY run's row can lag the orchestrator queue, so a 404 means not yet
    And retry until responseStatus == 200 && ['COMPLETED', 'FAILED', 'ABORTED', 'SUBMISSION_FAILED'].includes(response.driverStatus)
    When method get
    Then status 200
    * def run = response
