@ignore
Feature: Check whether a starting compute is held back by a namespace quota or node capacity shortage.
  Called by create-compute.feature while it waits, so a full quota fails the wait early:
    karate.call('classpath:iomete/helpers/compute/check-resource-shortage.feature',
                { computeId: '...', computeName: 'my-compute', namespace: '...', since: <epoch ms> })
  Only events and log lines since the wait began count. Returns shortage (see resource-shortage.js),
  whose giveUp says when to stop waiting. It never fails on a status.

  Scenario: read the compute's events and recent driver log
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    Given url baseUrl
    And path computePath, computeId, 'events'
    When method get
    * def events = responseStatus == 200 && Array.isArray(response) ? response : []

    # executor pods the quota refuses never exist, so only the driver log names them
    Given url baseUrl
    And path computePath, computeId, 'logs'
    And param range = '5m'
    When method get
    * def logEntries = responseStatus == 200 && Array.isArray(response) ? response : []

    * def resourceShortage = read('classpath:iomete/helpers/namespace/resource-shortage.js')
    * def shortage = resourceShortage({ subject: 'compute ' + computeName, namespace: namespace, events: events, logEntries: logEntries, since: since })
