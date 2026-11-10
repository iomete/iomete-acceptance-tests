@lock=sql
Feature: Spark Connect, a compute answers over the Spark Connect connection string it advertises

  Everything else in the suite queries through the SQL editor API. This connects the way a
  PySpark or Scala client does: the compute's Spark Connect endpoint, filled in the way the
  console fills it (TLS, the user's name and an access token), through the public gateway.
  On a remote plane it connects to that plane's own host, as the console does.

  Background:
    * url baseUrl
    # only runs queries, so it borrows the run's shared SQL compute rather than starting one
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })

    Given path 'api/v2/domains/' + domain + '/compute', sqlCompute.result.computeId
    When method get
    Then status 200
    * def endpoints = response.endpoints

    Given path 'api/v1/user'
    When method get
    Then status 200
    * def username = response.username

    # the console's recipe: {host} is the public host and port, then TLS, the user and the token
    * def ssl = baseUrl.startsWith('https')
    * def authority = baseUrl.replace(/^https?:\/\//, '').split('/')[0]
    * def defaultPort = ssl ? ':443' : ':80'
    * def host = endpoints.resolvedHost ? endpoints.resolvedHost + defaultPort : (authority.indexOf(':') > 0 ? authority : authority + defaultPort)
    * def connectUrl = endpoints.sparkConnect.replace('{host}', host) + (ssl ? ';use_ssl=true' : '') + ';user_id=' + username + ';api_token={access_token}'
    * def SparkConnectClient = Java.type('iomete.helpers.connection.SparkConnectClient')
    # Optional custom SSL certificate for self-signed or custom CA certificates (IOMETE_SPARK_CONNECT_CERT)
    * def certPath = karate.get('sparkConnectCert')

  Scenario: the Spark Connect connection string runs a query and rejects a bad token
    * def rows = SparkConnectClient.query(connectUrl, token, "SELECT id, CONCAT('row-', id) AS label FROM VALUES (1), (2), (3) AS t(id) ORDER BY id", certPath)
    * match rows == [{ id: 1, label: 'row-1' }, { id: 2, label: 'row-2' }, { id: 3, label: 'row-3' }]

    # the gRPC status is what tells an authentication failure apart from any other
    * def rejected = SparkConnectClient.failure(connectUrl, 'karate-not-a-token', 'SELECT 1', certPath)
    * if (rejected == null || !/UNAUTHENTICATED|PERMISSION_DENIED/.test(rejected)) karate.fail('bad token was not rejected as unauthenticated: ' + rejected)
