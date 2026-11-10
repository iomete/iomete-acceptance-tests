Feature: Delete the fixtures this run owns, the suite's data teardown.

  Scoped deliberately to the fixtures listed in karate-config.js: the ones built once per run
  via callSingle and shared across features, so no single scenario knows when it is safe to
  drop them. Everything else a scenario creates, it deletes itself; that is the convention and
  this is not a substitute for it. A scenario that fails before its own cleanup still leaks
  until the run's domain is deleted, or for good, so prefer an afterScenario.

  Databases need a compute to drop. CI no longer stops the computes, so one is normally still
  up; when there is none this skips them rather than paying a cold start on every run.

  Run it with `make cleanup-run`. Targeted by path and never scanned, since helpers/ sits
  outside iomete/tests.

  Scenario: delete this run's fixtures
    * def removed = []
    * def failed = []

    # --- the security user ---------------------------------------------------------------
    # deleting a user leaves its grant rows behind, so revoke them while the compute still exists
    * karate.call('classpath:iomete/helpers/user/revoke-bundle-grants.feature', { username: fixtures.securityUser, computeName: fixtures.securityCompute })
    Given url baseUrl
    And path 'api/v1/admin/identity/users', fixtures.securityUser
    When method delete
    Then assert responseStatus == 404 || (responseStatus >= 200 && responseStatus < 300)
    * if (responseStatus != 404) removed.push(fixtures.securityUser)

    # --- the maintenance catalog ---------------------------------------------------------
    Given url baseUrl
    And path 'api/v1/admin/spark/settings/catalogs', fixtures.maintenanceCatalog
    When method delete
    Then assert responseStatus == 404 || (responseStatus >= 200 && responseStatus < 300)
    * if (responseStatus != 404) removed.push(fixtures.maintenanceCatalog)

    # --- the catalog-sync job of the catalog features ------------------------------------------
    # a no-op when absent, so it is not counted among the removed; reported rather than failed
    # on, so a jobs outage cannot stop the databases and computes below from being dropped
    * def deleteSyncJob =
      """
      function() {
        try { karate.call('classpath:iomete/helpers/job/delete-job.feature', { name: fixtures.catalogSyncJob }); }
        catch (e) { failed.push(fixtures.catalogSyncJob + ': ' + e); }
      }
      """
    * deleteSyncJob()

    # --- the maintenance catalog's access policy -------------------------------------------
    # a no-op when absent, so it is not counted among the removed
    * karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'access', name: fixtures.maintenancePolicy })

    # --- the OIDC integration, if a cancelled run left it -------------------------------------
    # oidc-manual-endpoints deletes it itself; this only catches the afterScenario a cancel skipped.
    # The helper never touches an integration with another client. Reported rather than failed on
    * def deleteOidc =
      """
      function() {
        try {
          if (karate.call('classpath:iomete/helpers/settings/delete-oidc-integration.feature').removed) removed.push('OIDC integration ' + fixtures.oidcClient);
        } catch (e) { failed.push('OIDC integration ' + fixtures.oidcClient + ': ' + e); }
      }
      """
    * deleteOidc()

    # --- the databases, if this run's compute is up ---------------------------------------
    # named exactly rather than taking the first ACTIVE one: that would also match a compute
    # a scenario created and the pre-V2 compat compute, which cannot serve the V2 queries below
    Given url baseUrl
    And path 'api/v2/domains/' + domain + '/compute'
    When method get
    Then assert responseStatus == 200 || responseStatus == 404
    * def computes = responseStatus == 200 ? (response.items || response) : []
    * def liveCompute = computes.find(c => c.driverStatus == 'ACTIVE' && c.name == fixtures.sqlCompute)

    * def dropDatabases =
      """
      function() {
        if (!liveCompute) {
          karate.log('no ACTIVE compute, leaving the databases of this run behind; start a compute and run cleanup again to drop them');
          return;
        }
        var run = function(statement) {
          return karate.call('classpath:iomete/helpers/query/run-query-v2.feature',
                             { domain: domain, computeName: liveCompute.name, statement: statement }).result;
        };
        // built here, not as a step-level array literal: bare vars do not resolve in those
        var databases = [fixtures.db, fixtures.ddlDb, fixtures.dmlDb, fixtures.securityDb, fixtures.eventStreamDb, fixtures.catalogDb];
        // A run only creates the databases its features asked for, and SHOW TABLES throws on
        // one that does not exist, so ask what is actually there rather than per-database
        // try/catch, which would report every absent one as a failure.
        var existing = (run('SHOW DATABASES IN spark_catalog') || {}).values || [];
        for (var i = 0; i < databases.length; i++) {
          var db = databases[i];
          var bare = db.substring(db.lastIndexOf('.') + 1);
          if (existing.indexOf(bare) < 0) continue;
          try {
            // CASCADE leaves member rows behind on this catalog, so drop the tables first.
            // SHOW TABLES flattens to [namespace, tableName, isTemporary, ...].
            var rows = (run('SHOW TABLES IN ' + db) || {}).values || [];
            for (var t = 1; t < rows.length; t += 3) run('DROP TABLE IF EXISTS ' + db + '.' + rows[t]);
            run('DROP DATABASE IF EXISTS ' + db);
            removed.push(db);
          } catch (e) {
            failed.push(db + ': ' + e);
          }
        }
      }
      """
    * dropDatabases()

    # --- this run's computes, AFTER the databases they were needed to drop -----------------
    * def dropComputes =
      """
      function() {
        var names = [fixtures.sqlCompute, fixtures.securityCompute];
        for (var i = 0; i < names.length; i++) {
          // a run that never touched SQL or security features has nothing here
          if (!computes.find(c => c.name == names[i])) continue;
          try {
            karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: names[i] });
            removed.push(names[i]);
          } catch (e) {
            failed.push(names[i] + ': ' + e);
          }
        }
      }
      """
    * dropComputes()

    * eval java.lang.System.out.println('cleanup for run ' + runId + ': removed ' + removed.length + ' fixture(s)' + (removed.length ? ' [' + removed.join(', ') + ']' : ''))
    * eval if (failed.length) java.lang.System.out.println('cleanup could not remove: ' + failed.join('; '))

    # Teardown must not turn a green run red, so a fixture that would not delete is reported
    # and left behind rather than failed on.
    * match removed == '#present'
