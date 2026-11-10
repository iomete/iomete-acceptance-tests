@lock=sql
Feature: Storage browser, a table this run wrote can be found in its catalog's bucket

  The console's storage browser lists a catalog's object storage with the catalog's own
  credentials, read by iom-core. So the scenario looks up where the run's seeded table lives and
  walks down to it: the bucket is listed, the table folder holds Iceberg's data and metadata
  folders, and those hold the files the seeding just wrote. Only a real bucket can answer that.

  Not tested here: paging through long listings and the errors for catalogs without S3 storage,
  which stay in iom-core's own tests.

  Background:
    * url baseUrl
    # seeds this run's database from setup/data/ fixtures, once per run
    * def testData = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def catalogName = testData.database.split('.')[0]
    * def table = testData.database + '.employees'
    * def browserPath = 'api/v1/domains/' + domain + '/s3-browser/' + catalogName

  Scenario: the seeded table's data and metadata files are listed under its location
    # iom-core reads spark_catalog with the control plane's default storage, which a remote plane may not share
    * if (isRemotePlane(testData.compute.computeDataPlane)) { karate.log('skipping: compute ' + testData.computeName + ' is on remote data plane ' + testData.compute.computeDataPlane + ', whose storage the browser may not reach'); karate.abort() }
    # where the catalog put the table: DESCRIBE EXTENDED rows come back flattened as
    # [col_name, data_type, comment, ...], and the Location row is in the detailed section
    * def described = karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: testData.computeName, statement: 'DESCRIBE TABLE EXTENDED ' + table }).result
    * def locationOf = function(values){ for (var i = 0; i < values.length; i += 3) { if (values[i] == 'Location') return values[i + 1]; } return null }
    * def location = locationOf(described.values || [])
    And match location == '#string'
    # the browser only serves S3 catalogs, so another storage has nothing to list here
    * if (!/^s3a?:\/\//.test(location)) karate.log('table location ' + location + ' is not on S3, the storage browser cannot list it, skipping')
    * if (!/^s3a?:\/\//.test(location)) karate.abort()
    * def bucket = location.replace(/^s3a?:\/\//, '').split('/')[0]
    * def tablePrefix = location.replace(/^s3a?:\/\/[^\/]+\//, '').replace(/\/$/, '') + '/'

    Given path browserPath, 'buckets'
    When method get
    Then status 200
    And match response contains bucket

    Given path browserPath, 'list'
    And param bucket = bucket
    And param prefix = tablePrefix
    When method get
    Then status 200
    And match response.bucketName == bucket
    And match response.folders contains only [ '#(tablePrefix + "data/")', '#(tablePrefix + "metadata/")' ]

    Given path browserPath, 'list'
    And param bucket = bucket
    And param prefix = tablePrefix + 'data/'
    When method get
    Then status 200
    * def dataFiles = response.files.filter(f => f.key.endsWith('.parquet') && f.size > 0)
    And assert dataFiles.length > 0

    Given path browserPath, 'list'
    And param bucket = bucket
    And param prefix = tablePrefix + 'metadata/'
    When method get
    Then status 200
    * def metadataFiles = response.files.filter(f => f.key.endsWith('.metadata.json'))
    And assert metadataFiles.length > 0
