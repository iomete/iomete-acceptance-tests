@lock=api
Feature: Admin visibility into enrolled data planes

  Read-only, system-admin endpoints over the data-plane resource itself — enrollment,
  connectivity, identity. No fixtures of their own: data planes are the target environment's
  own topology, not something this suite creates. Every target has at least one CONNECTED
  plane, but which one is the target's business ('default' on most installs, only
  enrolled planes on a planes-only target), so the scenarios anchor on a connected plane,
  never on the name 'default'.

  `/api/v1/admin/multi-cluster/data-planes` (list/get) needs the ADMINISTRATION_MANAGER admin
  role specifically, not just any admin role — the suite's root admin account has it, but a
  403 here is the first thing to check if that ever stops being true.

  Namespace and quota fan-out across data planes lives in tests/namespace/ instead: those
  endpoints are namespace behavior with dataPlane as one more field on each row, not
  data-plane behavior, so they belong with the rest of the namespace coverage.

  Background:
    * url baseUrl
    * def dataPlanesPath = 'api/v1/admin/multi-cluster/data-planes'

  Scenario: every enrolled data plane is listed, at least one of them connected
    Given path dataPlanesPath
    When method get
    Then status 200
    And match response == '#[_ > 0]'
    And match each response contains { id: '#string', displayName: '#string', status: '#string', address: '#string', version: '#string' }
    * def connected = response.filter(dp => dp.status == 'CONNECTED')
    And match connected == '#[_ > 0]'
    And match connected[0] contains { healthCheckedAt: '#string' }

  Scenario: getting one data plane by id returns its detail, with its per-namespace quotas
    Given path dataPlanesPath
    When method get
    Then status 200
    * def anchorPlane = response.find(dp => dp.status == 'CONNECTED')
    And match anchorPlane == '#notnull'

    Given path dataPlanesPath, anchorPlane.id
    When method get
    Then status 200
    And match response contains { id: '#(anchorPlane.id)', status: 'CONNECTED' }
    And match response.namespaces == '#array'

  Scenario: every connected data plane keeps checking in
    # the admin ping is not routed by the gateway; each report moves healthCheckedAt instead
    Given path dataPlanesPath
    When method get
    Then status 200
    * def connected = response.filter(dp => dp.status == 'CONNECTED')
    And match connected == '#[_ > 0]'
    And match each connected contains { healthCheckedAt: '#string' }
    * def before = connected.reduce((m, dp) => { m[dp.id] = dp.healthCheckedAt; return m }, {})

    * def allCheckedInAgain = function(planes) { return Object.keys(before).every(id => { var dp = planes.find(p => p.id == id); return dp && dp.status == 'CONNECTED' && dp.healthCheckedAt != before[id] }) }
    * configure retry = { count: 12, interval: 5000 }
    Given path dataPlanesPath
    And retry until responseStatus == 200 && allCheckedInAgain(response)
    When method get
    * match before == '#? Object.keys(_).length > 0'
