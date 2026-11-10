@lock=maintenance
Feature: Maintenance, an admin turns automated table maintenance on and off for a catalog

  Automated maintenance (compaction, snapshot expiry, manifest rewrites, orphan file cleanup) is
  configured per catalog. What is worth proving is not that the API accepts the request: the
  settings have no table of their own, iom-maintenance writes them straight onto the Iceberg
  catalog as catalog properties through iom-core and reads them back from there, layering the
  platform defaults underneath. That round trip only means something with the real catalog behind
  it, so it belongs here rather than inside the service.

  The catalog comes from the setup feature, because spark_catalog is excluded from maintenance and
  it is the only catalog every environment is guaranteed to have.

  Background:
    * def setup = karate.callSingle('classpath:iomete/tests/maintenance/setup/maintenance-catalog.feature', { domain: domain })
    * def catalogName = setup.catalogName
    * def compactionPath = 'api/v1/domains/' + domain + '/compaction/catalogs/' + catalogName
    * def configPath = compactionPath + '/config'

    * def enableRequest =
      """
      {
        maintenanceEnabled: { value: 'true' },
        operations: {
          rewriteDataFiles: { enabled: { value: 'true' } },
          rewriteManifestFiles: { enabled: { value: 'true' } },
          expireSnapshots: { enabled: { value: 'true' } },
          cleanupOrphanFiles: { enabled: { value: 'true' } }
        }
      }
      """

  Scenario: enabling maintenance for a catalog reads back with every operation on
    Given url baseUrl
    And path configPath
    And request enableRequest
    When method put
    Then status 200
    And match response.catalog == catalogName

    # read it back on a request of its own, so the assertions are on stored state, not on the echo
    Given url baseUrl
    And path configPath
    When method get
    Then status 200
    And match response.maintenanceEnabled.value == 'true'
    And match response.operations.rewriteDataFiles.enabled.value == 'true'
    And match response.operations.rewriteManifestFiles.enabled.value == 'true'
    And match response.operations.expireSnapshots.enabled.value == 'true'
    And match response.operations.cleanupOrphanFiles.enabled.value == 'true'

    # the admin API reads the same stored config: one call proves its route and admin auth reach
    # the service; everything past that is the code the domain API above already ran
    Given url baseUrl
    And path 'api/v1/admin/compaction/catalogs', catalogName, 'config'
    When method get
    Then status 200
    And match response.catalog == catalogName
    And match response.maintenanceEnabled.value == 'true'
    And match response.operations.rewriteDataFiles.enabled.value == 'true'

    # the settings really landed on the catalog itself, which is the part a fake backend could not fake
    Given url baseUrl
    And path 'api/v1/admin/spark/settings/catalogs', catalogName
    When method get
    Then status 200
    * def properties = karate.map(response.properties, function(p){ return p.key + '=' + p.value })
    And match properties contains 'iomete.maintenance.enabled=true'
    And match properties contains 'iomete.maintenance.rewrite-data-files.enabled=true'
    And match properties contains 'iomete.maintenance.rewrite-manifest-files.enabled=true'
    And match properties contains 'iomete.maintenance.expire-snapshots.enabled=true'
    And match properties contains 'iomete.maintenance.cleanup-orphan-files.enabled=true'

  Scenario: disabling maintenance flips the catalog off and leaves the per-operation settings alone
    # enable first, so the disable has something to switch off whatever an earlier run left behind
    Given url baseUrl
    And path configPath
    And request enableRequest
    When method put
    Then status 200

    Given url baseUrl
    And path compactionPath + '/disable-maintenance'
    When method post
    Then status 204

    # only the master switch moved, so turning it back on would restore the rest as they were
    Given url baseUrl
    And path configPath
    When method get
    Then status 200
    And match response.maintenanceEnabled.value == 'false'
    And match response.operations.rewriteDataFiles.enabled.value == 'true'
    And match response.operations.rewriteManifestFiles.enabled.value == 'true'
    And match response.operations.expireSnapshots.enabled.value == 'true'
    And match response.operations.cleanupOrphanFiles.enabled.value == 'true'
