@ignore
Feature: Read the last 15 minutes of one compute pod's log, whatever the status (plumbing).
  Used by log-compute-diagnostics.feature, call it with:
    karate.call('classpath:iomete/helpers/compute/read-instance-logs.feature', { computeId: '...', instanceName: '...' })
  and read `status` and `body`. It never fails on the status.

  Scenario: read the pod's log
    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/compute', computeId, 'instances', instanceName, 'logs'
    And param range = '15m'
    When method get
    * def status = responseStatus
    * def body = response
