@lock=sql
Feature: Client connections, a compute answers over Thrift and Arrow Flight with the connection string it advertises

  Everything else in the suite queries through the SQL editor API. These scenarios connect the
  way a BI tool or a script does: a JDBC driver, the connection string from the compute's
  endpoints, the user's id and an access token as the password, through the public gateway.

  Arrow Flight runs wherever the shared SQL compute lands: on a remote plane it connects to that
  plane's own host, as the console does. Thrift is local-plane only, so it skips on a remote one.

  Background:
    * url baseUrl
    # only runs queries, so it borrows the run's shared SQL compute rather than starting one
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })

    Given path 'api/v2/domains/' + domain + '/compute', sqlCompute.result.computeId
    When method get
    Then status 200
    * def endpoints = response.endpoints
    # the user id the console shows next to the connection string, for whoever owns the token
    Given path 'api/v1/user'
    When method get
    Then status 200
    * def userId = response.id
    * def JdbcClient = Java.type('iomete.helpers.connection.JdbcClient')

    * def probe = "SELECT id, CONCAT('row-', id) AS label FROM VALUES (1), (2), (3) AS t(id) ORDER BY id"
    * def expectedRows = [{ id: 1, label: 'row-1' }, { id: 2, label: 'row-2' }, { id: 3, label: 'row-3' }]

  Scenario: the Thrift (Hive JDBC) connection string runs a query and rejects a bad token
    * if (isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('skipping: compute ' + sqlCompute.computeName + ' is on remote data plane ' + sqlCompute.computeDataPlane); karate.abort() }
    * def thriftUrl = endpoints.jdbc.replace('{host}', gatewayHostPort).replace('{ssl}', '' + gatewaySsl)

    * def rows = JdbcClient.query(thriftUrl, userId, token, probe)
    * match rows == expectedRows

    # only an authentication answer counts, so a timeout or gateway error cannot pass as a rejection
    * def rejected = JdbcClient.failure(thriftUrl, userId, 'karate-not-a-token', probe)
    * if (rejected == null || !/\b(401|403)\b|Unauthorized|Forbidden/i.test(rejected)) karate.fail('bad token was not rejected as unauthenticated: ' + rejected)

  Scenario: the Arrow Flight SQL connection string runs a query and rejects a bad token
    # the console only offers Arrow Flight when this module is on, so neither does the test
    * if (!arrowFlightEnabled) { karate.log('skipping: arrowFlightConnection is off on ' + baseUrl); karate.abort() }

    * match endpoints.arrowFlightJdbc == '#string'
    # a remote plane's compute is reached on that plane's host, which the API resolves for us
    * def flightHost = endpoints.resolvedHost ? endpoints.resolvedHost + (gatewaySsl ? ':443' : ':80') : gatewayHostPort
    * def flightUrl = endpoints.arrowFlightJdbc.replace('{host}', flightHost) + '&useEncryption=' + gatewaySsl

    * def rows = JdbcClient.query(flightUrl, userId, token, probe)
    * match rows == expectedRows

    # the gRPC status is what tells an authentication failure apart from any other
    * def rejected = JdbcClient.failure(flightUrl, userId, 'karate-not-a-token', probe)
    * if (rejected == null || !/UNAUTHENTICATED|PERMISSION_DENIED/.test(rejected)) karate.fail('bad token was not rejected as unauthenticated: ' + rejected)
