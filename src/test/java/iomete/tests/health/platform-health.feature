@lock=api
Feature: Platform health

  The check support and monitoring do by hand on a new environment: the control plane says it
  is up and every tracked service is healthy right now.

  Background:
    * url baseUrl

  Scenario: the control plane is up and every tracked service is operational
    # rows for a plane that is not connected say nothing about the planes in use
    Given path 'api/v1/admin/multi-cluster/data-planes'
    When method get
    Then status 200
    * def connectedIds = response.filter(dp => dp.status == 'CONNECTED').map(dp => dp.id)

    # a service under load can report a passing blip, so poll; one that stays down still fails.
    # The last poll ends the retry, so the checks below fail naming the status or the services, not
    # a bare timeout
    * def unhealthyOf = function(list){ return list.filter(s => (!s.dataPlane || connectedIds.includes(s.dataPlane)) && s.now.status != 'OPERATIONAL').map(s => s.service + (s.dataPlane ? ' @ ' + s.dataPlane : '') + ': ' + s.now.status) }
    * def AtomicInteger = Java.type('java.util.concurrent.atomic.AtomicInteger')
    * def polls = new AtomicInteger(0)
    # Karate's retry count is the number of requests, so the last one is the retry's last
    * def maxPolls = 24
    * def settled = function(status, list){ var last = polls.incrementAndGet() >= maxPolls; return last || (status == 200 && unhealthyOf(list).length == 0) }
    * configure retry = { count: '#(maxPolls)', interval: 5000 }
    Given path 'api/v2/health-check'
    And retry until settled(responseStatus, response)
    When method get
    Then status 200
    And match response[*].service contains 'Core Service'
    And match unhealthyOf(response) == []

    # the load balancer check, which needs no token
    * configure headers = null
    Given path 'api/v1/health-check/control-plane'
    When method get
    Then status 200
    And match response == { status: 'UP' }
