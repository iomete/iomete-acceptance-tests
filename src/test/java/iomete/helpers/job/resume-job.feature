@ignore
Feature: Resume a suspended Spark job (plumbing).
  Undoes the suspend that delete-job.feature applies, for a job the delete then left behind:
    karate.call('classpath:iomete/helpers/job/resume-job.feature', { jobId: job.jobId })

  Scenario: clear the suspend flag so the schedule fires again
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/spark/jobs', jobId, 'suspend'
    And request { suspend: false }
    When method put
    Then assert responseStatus >= 200 && responseStatus < 300
