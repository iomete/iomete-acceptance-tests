@lock=maintenance
Feature: Maintenance, an admin overrides the catalog's maintenance settings for one table

  Table settings have no table of their own either: iom-maintenance writes them onto the Iceberg
  table as table properties through the REST catalog and reads them back from there, with the
  catalog's settings underneath. Spark reading those properties from the same table is what
  proves they landed on the table itself, and that needs the real catalog behind it.

  The table is this run's own and is dropped afterwards. It lives in the run's maintenance catalog,
  because spark_catalog is excluded from maintenance.

  Background:
    * url baseUrl

    * def setup = karate.callSingle('classpath:iomete/tests/maintenance/setup/maintenance-db.feature', { domain: domain })
    * def catalogName = setup.catalogName
    * def computeName = setup.computeName
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }

    * def database = setup.database
    * def tableName = 'karate_table_config_' + runId
    * def qualified = catalogName + '.' + database + '.' + tableName
    * def catalogConfigPath = 'api/v1/domains/' + domain + '/compaction/catalogs/' + catalogName + '/config'
    * def tableConfigPath = 'api/v1/domains/' + domain + '/compaction/catalogs/' + catalogName + '/databases/' + database + '/tables/' + tableName + '/config'

    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/query/run-query-v2.feature',
                    { domain: domain, computeName: computeName, statement: 'DROP TABLE IF EXISTS ' + qualified });
      }
      """

  Scenario: a table's maintenance settings land on the Iceberg table as properties
    * runQuery('CREATE TABLE IF NOT EXISTS ' + qualified + ' (id INT)')

    # a table cannot turn maintenance on while its catalog has it off
    Given path catalogConfigPath
    And request { maintenanceEnabled: { value: 'true' } }
    When method put
    Then status 200

    # one operation on, one off, so the read-back shows the table's own values, not one default
    Given path tableConfigPath
    And request
      """
      {
        maintenanceEnabled: { value: 'true' },
        operations: {
          rewriteDataFiles: { enabled: { value: 'true' } },
          expireSnapshots: { enabled: { value: 'false' } }
        }
      }
      """
    When method put
    Then status 200

    Given path tableConfigPath
    When method get
    Then status 200
    And match response.table == tableName
    And match response.maintenanceEnabled.value == 'true'
    And match response.operations.rewriteDataFiles.enabled.value == 'true'
    And match response.operations.expireSnapshots.enabled.value == 'false'

    # Spark reads the same table: the settings are on it, not in the service. The service wrote
    # them through the REST catalog, behind Spark's back, so drop Spark's cached copy first
    * runQuery('REFRESH TABLE ' + qualified)
    * def shown = runQuery('SHOW TBLPROPERTIES ' + qualified)
    * def width = shown.columns.length
    * def properties = []
    * eval for (var i = 0; i + 1 < shown.values.length; i += width) properties.push(shown.values[i] + '=' + shown.values[i + 1])
    And match properties contains 'iomete.maintenance.enabled=true'
    And match properties contains 'iomete.maintenance.rewrite-data-files.enabled=true'
    And match properties contains 'iomete.maintenance.expire-snapshots.enabled=false'
