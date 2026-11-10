@ignore
Feature: Stop and remove a streaming job by name, if it is still there (plumbing).
  Teardown helper, safe to call when the job is already gone:
    karate.call('classpath:iomete/helpers/job/delete-streaming-job.feature', { name: 'my-job' })

  Streaming jobs are left out of the regular job listings, so delete-job.feature cannot find
  them. A job is refused deletion while its application runs, and an application still being
  aborted counts as running, so the delete is retried until it is accepted.

  Scenario: stop the job's application and delete it, or do nothing
    * def streamingPath = 'api/v2/domains/' + domain + '/spark/streaming/jobs'
    Given url baseUrl
    And path streamingPath
    And params { search: '#(name)', page: 0, size: 100 }
    When method get
    Then status 200
    * def found = response.items.find(j => j.name == name)
    * if (found == null) karate.abort()

    # 404: no application is running; 409: one is already being stopped
    Given url baseUrl
    And path streamingPath, found.id, 'stop'
    When method post
    Then assert responseStatus == 200 || responseStatus == 404 || responseStatus == 409

    * configure retry = { count: 12, interval: 5000 }
    Given url baseUrl
    And path streamingPath, found.id
    And retry until responseStatus != 409
    When method delete
    Then assert responseStatus < 300 || responseStatus == 404
