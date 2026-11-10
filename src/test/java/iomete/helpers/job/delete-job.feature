@ignore
Feature: Remove a Spark job by name, if it is still there (plumbing).
  Teardown counterpart to create-job.feature, safe to call when the job is already gone:
    karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: 'my-job' })

  Suspends before deleting, so a scheduled job stops firing runs even when the delete itself is
  refused (the API rejects a delete while a run is still active).

  Scenario: suspend and delete the job, or do nothing if it does not exist
    * def jobsPath = 'api/v1/domains/' + domain + '/spark/jobs'

    Given url baseUrl
    And path jobsPath
    When method get
    Then status 200
    * def job = response.find(j => j.name == name)
    * if (job == null) karate.abort()

    Given url baseUrl
    And path jobsPath, job.id, 'suspend'
    And request { suspend: true }
    When method put
    Then assert responseStatus < 500

    Given url baseUrl
    And path jobsPath, job.id
    When method delete
    Then assert responseStatus < 500
