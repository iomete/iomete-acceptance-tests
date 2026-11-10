@ignore
Feature: Kill one run, tolerating one that has already finished (plumbing).
  Called by kill-active-runs.feature with runsPath and runId.

  Scenario: kill the run
    Given url baseUrl
    And path runsPath, runId
    When method delete
    # 409: it reached a final state in the meantime
    Then assert responseStatus < 300 || responseStatus == 404 || responseStatus == 409
