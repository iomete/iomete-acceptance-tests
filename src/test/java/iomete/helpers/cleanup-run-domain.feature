Feature: Delete the domain this run created, and say what stays behind.

  The last teardown step: run it after cleanup-run, which needs the run's SQL compute to drop
  its databases. Deleting the domain removes everything still running in it. Shared objects
  outside the domain stay, and are listed as a warning.

  Run it with `make cleanup-run-domain`. Targeted by path and never scanned, since helpers/
  sits outside iomete/tests.

  Scenario: delete the run's domain
    * def warn = function(line){ java.lang.System.out.println('WARNING: ' + line) }
    * def kept = ['the karate-* node types, which the next run reuses']
    * if (dataAccessAuditEnabled) kept.push('the data access audit table, spark_catalog.iomete_system_db.data_access_audit')

    * if (!domainOwnedByRun && !platformAtLeast('4.0.2')) kept.push('domain ' + domain + ': this platform cannot delete domains before 4.0.2')
    * if (!domainOwnedByRun && platformAtLeast('4.0.2')) kept.push('domain ' + domain + ': set by IOMETE_DOMAIN, so the suite does not own it')
    * if (!domainOwnedByRun) karate.forEach(kept, warn)
    * if (!domainOwnedByRun) karate.abort()

    * def removed = []
    * def failed = []
    * def deleteDomain = function(id){ var r = karate.call('classpath:iomete/helpers/domain/delete-domain.feature', { domain: id }); r.removed.forEach(x => removed.push(x)); r.failed.forEach(x => failed.push(x)) }
    * deleteDomain(domain)

    # the extra domains a scenario makes (karate-rv-<run id>-*, karate-ns-<run id>-*), which a cancelled run never deleted
    Given url baseUrl
    And path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def listed = response
    * def extra = listed.filter(d => d.id.startsWith('karate-rv-' + runId + '-') || d.id.startsWith('karate-ns-' + runId + '-'))
    * karate.forEach(extra, d => deleteDomain(d.id))

    # the private domains a scenario makes (karate-priv-<run id>-*): no admin can list or delete
    # their catalogs, so these go through their owner
    * def deletePrivateDomain = function(id){ var r = karate.call('classpath:iomete/helpers/domain/delete-private-domain.feature', { domain: id }); r.removed.forEach(x => removed.push(x)); r.failed.forEach(x => failed.push(x)) }
    * def leftPrivate = listed.filter(d => d.id.startsWith('karate-priv-' + runId + '-'))
    * karate.forEach(leftPrivate, d => deletePrivateDomain(d.id))

    # straight to stdout: `print` only reaches the HTML report
    * eval java.lang.System.out.println('run ' + runId + ': removed ' + removed.length + ' item(s)' + (removed.length ? ': ' + removed.join(', ') : ''))
    * karate.forEach(kept, warn)
    * match failed == []
