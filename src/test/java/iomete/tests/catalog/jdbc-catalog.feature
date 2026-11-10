@lock=sql
Feature: JDBC catalog, a connection string is attachable and checked through Spark

  A JDBC catalog exposes another database's tables to Spark. The platform takes the connection
  string, user, password and driver as catalog properties and hands them to Spark as they are.
  The connection check is the integration under test: it runs real statements through Spark
  against the supplied connection string.
  The suite has no external database to point at, so it loops back: the catalog's connection
  string is the shared SQL compute's own Hive JDBC (jdbc:hive2) one, with the run's token as
  the password, the same string the console offers a BI tool. Thrift is local-plane only, so
  this skips when that compute lands on a remote plane.

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * if (isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('skipping: compute ' + sqlCompute.computeName + ' is on remote data plane ' + sqlCompute.computeDataPlane); karate.abort() }

    Given path 'api/v2/domains/' + domain + '/compute', sqlCompute.result.computeId
    When method get
    Then status 200
    # the console fills {host} with the public host and port; the driver needs the port spelled out
    * def ssl = baseUrl.startsWith('https')
    * def authority = baseUrl.replace(/^https?:\/\//, '').split('/')[0]
    * def hostPort = authority.indexOf(':') > 0 ? authority : authority + (ssl ? ':443' : ':80')
    * def jdbcUrl = response.endpoints.jdbc.replace('{host}', hostPort).replace('{ssl}', '' + ssl)

    Given path 'api/v1/user'
    When method get
    Then status 200
    * def userId = response.id

    * def catalogsPath = 'api/v1/admin/spark/settings/catalogs'
    # unique per attempt, not just per run: Spark caches a loaded catalog by name, and a retry
    # mints a new token, so a reused name would answer with the revoked one
    * def catalogName = 'karate_jdbc_' + runId + '_' + java.util.UUID.randomUUID().toString().substring(0, 8)
    * def catalogRequest =
      """
      function(name, password) {
        return {
          name: name,
          description: 'JDBC catalog under test, managed by iomete/tests/catalog/jdbc-catalog.feature',
          catalogType: { type: 'jdbc', classification: 'external' },
          properties: [
            { key: 'url', value: jdbcUrl },
            { key: 'user', value: userId },
            { key: 'password', value: password },
            { key: 'driver', value: 'org.apache.hive.jdbc.HiveDriver' }
          ]
        };
      }
      """

    # the check runs real statements through the shared Spark Connect service, which can be slow on a cold start
    * configure readTimeout = 300000

    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/catalog/delete-catalog.feature', { catalogName: catalogName });
      }
      """

  Scenario: a JDBC catalog's connection string reaches its database, and the catalog reads back with the password masked
    # the check takes the catalog definition in the body, so it runs before anything is created
    Given path 'api/v1/admin/spark/settings/catalog-connection-check'
    And request catalogRequest(catalogName, token)
    When method post
    Then status 200
    # only listing is asserted: Spark's generic JDBC dialect quotes CREATE TABLE columns in a way
    # Spark SQL reads as string literals, so the check's create step fails on a hive2 target
    And match response['Show Tables'] == { success: true, errorMessage: '##null' }

    # control: the same connection string with a wrong password must fail, or the pass above
    # proves nothing about the credentials. A fresh name, because Spark caches a loaded catalog
    # by name and would answer with the one it just loaded.
    Given path 'api/v1/admin/spark/settings/catalog-connection-check'
    And request catalogRequest(catalogName + '_ctl', 'karate-not-a-token')
    When method post
    Then status 200
    And match response['Show Tables'].success == false
    And match response['Show Tables'].errorMessage contains 'HTTP Response code: 401'

    # 409 = a repeated test-one run already attached it
    Given path catalogsPath
    And request catalogRequest(catalogName, token)
    When method post
    Then assert responseStatus == 200 || responseStatus == 409

    Given path catalogsPath, catalogName
    When method get
    Then status 200
    And match response.catalogType contains { type: 'jdbc', classification: 'external' }
    And match response.properties contains { key: 'url', value: '#(jdbcUrl)' }
    And match response.properties contains { key: 'password', value: '********' }
