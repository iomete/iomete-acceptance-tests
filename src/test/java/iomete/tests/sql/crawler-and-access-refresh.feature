@lock=sql
Feature: SQL — the crawler registers an Iceberg table from storage, and a compute refreshes its access rules

  Two iom-sql endpoints that only mean something against the real platform. The crawler reads
  an Iceberg table's folder in object storage with the catalog's own credentials and registers
  it under a new name, so a table this run wrote is registered a second time and has to answer
  the same rows. The access refresh asks a running compute's driver, through the Flight proxy,
  to reload its Ranger policies and tags, which the shared SQL compute enables
  (`spark.iomete.arrow.flight.refreshActions.enabled`, set in its setup feature).

  Background:
    * url baseUrl
    # seeds this run's database from setup/data/ fixtures, once per run
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = testData.computeName
    * def database = testData.database
    * def catalogName = database.split('.')[0]
    * def namespace = database.split('.')[1]
    * def runQuery = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: statement }).result }

  Scenario: an Iceberg table this run wrote is registered from its storage folder and answers the same rows
    # scenario-owned, named per run like everything else, and both dropped here: the registered
    # copy shares the source's data files, so neither is left to cleanup-run
    * def sourceTable = 'karate_crawler_src_' + runId
    * def registeredTable = 'karate_crawler_registered_' + runId
    * def source = database + '.' + sourceTable
    * def registered = database + '.' + registeredTable
    * def drop = function(table){ karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: 'DROP TABLE IF EXISTS ' + table }) }
    * configure afterScenario = function(){ drop(registered); drop(source) }

    * runQuery('CREATE OR REPLACE TABLE ' + source + ' (id INT, label STRING)')
    * runQuery("INSERT INTO " + source + " VALUES (1, 'a'), (2, 'b'), (3, 'c')")
    # a test-one repeat keeps the run id, so the registered name can still be taken
    * runQuery('DROP TABLE IF EXISTS ' + registered)

    # where the catalog put the table: DESCRIBE EXTENDED rows come back flattened as
    # [col_name, data_type, comment, ...], and the Location row is in the detailed section
    * def described = runQuery('DESCRIBE TABLE EXTENDED ' + source)
    * def locationOf = function(values){ for (var i = 0; i < values.length; i += 3) { if (values[i] == 'Location') return values[i + 1]; } return null }
    * def location = locationOf(described.values || [])
    And match location == '#string'
    # the crawler reads S3 only (s3:// or s3a://); on any other storage it refuses by design
    * if (!/^s3a?:\/\//.test(location)) karate.log('table location ' + location + ' is not on S3, the crawler cannot read it here, skipping')
    * if (!/^s3a?:\/\//.test(location)) karate.abort()

    Given path 'api/v1/domains/' + domain + '/sql/crawler/registerIcebergTable'
    And request { icebergTableFolder: '#(location)', targetCatalogName: '#(catalogName)', targetDatabase: '#(namespace)', targetTableName: '#(registeredTable)' }
    When method post
    Then status 200
    And match response.totalRecordsCount == 3
    And assert response.totalDataFilesCount >= 1
    And match response.currentSnapshotId == '#number'

    # the registered table is the same data under another name
    * def count = runQuery('SELECT COUNT(*) AS total FROM ' + registered)
    And match count.values == [3]
    * def labels = runQuery('SELECT label FROM ' + registered + ' ORDER BY label')
    And match labels.values == ['a', 'b', 'c']

  Scenario: the shared compute reloads its access policies and tags on request
    # the endpoint has no domain to find the compute by, so the caller names its plane; before
    # 4.0.2 iom-sql ignored it and always dialed the local Flight proxy; from 4.0.2 a
    # remote-plane compute is reachable
    * def computePlane = sqlCompute.computeDataPlane
    * if (isRemotePlane(computePlane) && !platformAtLeast('4.0.2')) { karate.log('skipping: compute ' + sqlCompute.computeName + ' is on remote data plane ' + computePlane + ', which the access refresh reaches from 4.0.2; platform is ' + platformVersion); karate.abort() }
    # a local compute sends no plane, the same request as before
    * def planeParams = isRemotePlane(computePlane) ? { dataPlane: computePlane } : {}

    # the endpoint addresses a compute by its Kubernetes namespace and name, which the listing has
    Given path 'api/v2/domains/' + domain + '/compute'
    When method get
    Then status 200
    * def compute = response.items.find(c => c.name == computeName)
    And match compute == '#notnull'
    * def computeNamespace = compute.namespace
    And match computeNamespace == '#string'

    # 204 is the driver's answer after it has reloaded. 501 means the compute runs without the
    # refresh actions: the setup's 409 reuse path keeps an older compute as it is, so name it
    # rather than let the status assertion puzzle a test-one repeat
    Given path 'api/v1/admin/sql/computes', computeNamespace, computeName, 'refresh-access-policies'
    And params planeParams
    When method post
    * if (responseStatus == 501) karate.fail('compute "' + computeName + '" runs without spark.iomete.arrow.flight.refreshActions.enabled (created before the setup set it); delete it so the next run recreates it')
    Then status 204

    Given path 'api/v1/admin/sql/computes', computeNamespace, computeName, 'refresh-access-tags'
    And params planeParams
    When method post
    Then status 204
