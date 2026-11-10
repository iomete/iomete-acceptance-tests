@ignore
Feature: Stop a streaming job's application, if one is running (plumbing).
    karate.call('classpath:iomete/helpers/job/stop-streaming-job.feature', { jobId: job.id })

  Scenario: stop the job's application
    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/spark/streaming/jobs', jobId, 'stop'
    When method post
    # 404: no application is running; 409: one is already being stopped
    Then assert responseStatus == 200 || responseStatus == 404 || responseStatus == 409
