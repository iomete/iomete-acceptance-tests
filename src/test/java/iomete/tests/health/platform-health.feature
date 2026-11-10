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

    # a service under load can report a passing blip, so poll; one that stays down still fails
    * def unhealthyOf = function(list){ return list.filter(s => (!s.dataPlane || connectedIds.includes(s.dataPlane)) && s.now.status != 'OPERATIONAL').map(s => s.service + (s.dataPlane ? ' @ ' + s.dataPlane : '') + ': ' + s.now.status) }
    * configure retry = { count: 24, interval: 5000 }
    Given path 'api/v2/health-check'
    And retry until responseStatus == 200 && unhealthyOf(response).length == 0
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
