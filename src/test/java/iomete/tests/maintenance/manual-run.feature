@lock=maintenance
Feature: Maintenance, the runs that were asked for actually run

  A triggered run has to be picked up, run against the table, and land in the history the
  console reads. Whether the trigger itself is taken or refused belongs in the service's own
  tests.

  A run only executes where the catalog has a compute and a service account bound to it, so the
  scenario binds its own. What would otherwise wait for ever runs on every environment.

  The compute is this scenario's own, created after the catalog and deleted afterwards. A compute
  only learns the catalogs that exist when it starts, and on one added later procedures never
  resolve, so the shared SQL compute, which a full run starts long before this catalog, cannot
  run maintenance. Kept for the rest of the run it would hold node pool capacity the other
  computes are waiting for, so it lives only as long as the scenario.

  The table is created fresh per run with six appends, so it has small files and one manifest per
  append to rewrite. Each rewrite is checked by its effect through Iceberg's own metadata tables
  (`.manifests`, `.files`), read before and after: a status alone would also pass if the rewrite
  did nothing. Two operations are covered because each is a different Spark procedure; the other
  two cannot show an effect here (expire snapshots and orphan cleanup only touch what is days old).

  Background:
    * url baseUrl

    * def catalog = karate.callSingle('classpath:iomete/tests/maintenance/setup/maintenance-catalog.feature', { domain: domain })
    * def catalogName = catalog.catalogName
    # keyed by image too: the image legs of one run share its id
    * def computeName = 'karate-maint-' + computeSuffix + '-' + runId
    * def serviceAccount = 'karate-maint-sa-' + runId
    * def stagingPolicy = 'karate-maint-staging-' + runId
    * def compactionPath = 'api/v1/domains/' + domain + '/compaction'
    * def runQuery = function(stmt){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: stmt }).result }

    * def database = 'karate_maintenance_db'
    # the run id says whose it is, the timestamp keeps a retry of the run off the last attempt's
    * def tableName = 'karate_manual_run_' + runId + '_' + java.lang.System.currentTimeMillis()
    * def qualified = catalogName + '.' + database + '.' + tableName
    * def tablePath = compactionPath + '/catalogs/' + catalogName + '/databases/' + database + '/tables/' + tableName
    * def countFiles = function(){ return parseInt(runQuery('SELECT count(*) FROM ' + qualified + '.files').values[0]) }
    * def countManifests = function(){ return parseInt(runQuery('SELECT count(*) FROM ' + qualified + '.manifests').values[0]) }

    # Teardown, pass or fail: the table, the staging policy, then the service account (grants
    # first, while the compute still resolves its bundle), then the compute. Every step runs
    # whatever the one before did, the compute last: a warm compute left behind costs the node
    # pool far more than the rest. The first failure is the one reported. The binding has no
    # delete endpoint and goes with the catalog.
    * configure afterScenario =
      """
      function() {
        var error = null;
        var step = function(fn) {
          try { fn(); } catch (e) { if (!error) error = e; }
        };
        step(function() { runQuery('DROP TABLE IF EXISTS ' + qualified); });
        step(function() { karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'access', name: stagingPolicy }); });
        step(function() { karate.call('classpath:iomete/helpers/user/revoke-bundle-grants.feature', { username: serviceAccount, computeName: computeName, domainRoot: true }); });
        step(function() { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: serviceAccount }); });
        step(function() { karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName }); });
        if (error) throw error;
      }
      """

  Scenario: triggered manifest and data-file rewrites run and change the table
    # a compute is reused as-is once it exists, and one a killed run left can predate the
    # catalog, so start from none
    * def cleared = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }
    # single node: a few small rewrites need no executor, and one less pod waits on the node pool
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)', singleNode: true, image: '#(sparkImage)' }
    * def onboarded = call read('classpath:iomete/tests/maintenance/setup/maintenance-service-account.feature') { computeName: '#(computeName)', serviceAccount: '#(serviceAccount)' }

    # On Spark 4 a rewrite stages its output in default_rewrite_catalog, which no policy covers,
    # so the account is denied INSERT there without this. It is shared rather than run-owned, so
    # only this account gets it, and only for this scenario. The run's catalog is listed too only
    # to keep the resource set unique per run: two policies on the same resources are refused.
    # in parentheses, or the step reads the array as JSON and keeps `catalogName + '.*'` as text
    * def stagingDatabases = ([ catalogName + '.*', 'default_rewrite_catalog.*' ])
    * def staging =
      """
      {
        name: '#(stagingPolicy)',
        description: 'iomete-api-testing-suite: maintenance rewrite staging for one run',
        resources: [ { databases: '#(stagingDatabases)', tables: ['*'], columns: ['*'] } ],
        allowPolicyItems: [ { users: ['#(serviceAccount)'], accesses: ['ALL'] } ]
      }
      """
    * def stagingCreated = call read('classpath:iomete/helpers/security/create-policy.feature') { kind: 'access', policy: '#(staging)' }

    # the catalog policy has had the compute's whole cold start to arrive
    * def dbCreated = runQuery('CREATE DATABASE IF NOT EXISTS ' + catalogName + '.' + database)
    * match dbCreated.status == 'COMPLETED'

    * def tableCreated = runQuery('CREATE TABLE ' + qualified + ' (id INT, label STRING)')
    * match tableCreated.status == 'COMPLETED'

    # one file per insert, so the table has small files worth rewriting rather than a single one
    * def insertRow = function(i){ return runQuery('INSERT INTO ' + qualified + ' VALUES (' + i + ", 'row-" + i + "')").status }
    * def inserts = karate.repeat(6, insertRow)
    * match each inserts == 'COMPLETED'

    * def filesBefore = countFiles()
    * assert filesBefore >= 6
    # one manifest per append too: Iceberg only merges them once there are 100
    * def manifestsBefore = countManifests()
    * assert manifestsBefore >= 6

    # a table cannot turn maintenance on while its catalog has it off
    Given path compactionPath + '/catalogs/' + catalogName + '/config'
    And request { maintenanceEnabled: { value: 'true' } }
    When method put
    Then status 200

    # Manifests first, with the data rewrite off: the scheduler would otherwise start rewriting the
    # same small files and commit against the table mid-run. It never picks manifests itself on a
    # table this small (its threshold is 1000), so this step races nothing.
    Given path tablePath + '/config'
    And request { maintenanceEnabled: { value: 'true' }, operations: { rewriteManifestFiles: { enabled: { value: 'true' } }, rewriteDataFiles: { enabled: { value: 'false' } } } }
    When method put
    Then status 200

    # The trigger reads the config fresh, but the run reads it through a cache that lives a
    # minute and is not cleared on save. Triggered sooner, a "disabled" cached by an earlier
    # scenario is accepted and then SKIPPED as "Operation disabled". Remove both waits once
    # saving the config clears that cache.
    * java.lang.Thread.sleep(65000)

    # Bound only now: a valid binding is what lets the scheduler run anything here, and the
    # catalog may already be enabled by another feature or an earlier attempt, so bound sooner it
    # could rewrite the table mid-insert, before the counts above.
    * def binding = { computeId: '#(created.computeId)', serviceAccountId: '#(serviceAccount)' }
    Given path compactionPath + '/catalogs/' + catalogName + '/resource-config'
    And request { domain: '#(domain)', resources: ['#(binding)'] }
    When method put
    Then status 200
    And match response.resources == ['#(binding)']

    * def operationArgs = { compactionPath: '#(compactionPath)', tablePath: '#(tablePath)', catalogName: '#(catalogName)', database: '#(database)', tableName: '#(tableName)' }
    * def manifestArgs = karate.merge(operationArgs, { operationType: 'rewriteManifestFiles' })
    * def manifests = call read('classpath:iomete/tests/maintenance/setup/run-maintenance-operation.feature') manifestArgs

    # the manifests were rewritten and nothing else was: Spark sees fewer manifests over the same
    # data files (the rewrite committed outside this session, so Spark's cached copy is stale)
    * runQuery('REFRESH TABLE ' + qualified)
    * def manifestsAfter = countManifests()
    * assert manifestsAfter < manifestsBefore
    * match countFiles() == filesBefore

    # now the data files; minInputFiles 2 makes the six of them one group worth rewriting
    # whatever the default is
    Given path tablePath + '/config'
    And request { maintenanceEnabled: { value: 'true' }, operations: { rewriteManifestFiles: { enabled: { value: 'true' } }, rewriteDataFiles: { enabled: { value: 'true' }, properties: { minInputFiles: { value: '2' } } } } }
    When method put
    Then status 200
    * java.lang.Thread.sleep(65000)

    # the scheduler sees the same small files once the data rewrite is on and may start its own
    # first; the helper follows that run then
    * def dataArgs = karate.merge(operationArgs, { operationType: 'rewriteDataFiles' })
    * def dataFiles = call read('classpath:iomete/tests/maintenance/setup/run-maintenance-operation.feature') dataArgs

    # the rewrite really happened on the table: Spark sees fewer data files than before
    * runQuery('REFRESH TABLE ' + qualified)
    * def filesAfter = countFiles()
    * assert filesAfter < filesBefore
