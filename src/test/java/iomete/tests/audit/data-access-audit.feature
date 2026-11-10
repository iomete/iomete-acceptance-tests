@lock=stream
Feature: Data access audit — reading a table shows up in the admin audit log

  What this checks:
  - After a query reads a table, the admin audit log lists that read: the table, that the
    access was allowed, and the user who ran it.

  How it gets there: the compute's security plugin records every table access and sends it to
  the platform's event stream, which writes it to the audit table; the admin audit endpoint
  reads it back from there. So the row only appears if all of those really work together.

  The audit table must exist first, as the docs tell an admin (see setup/audit-table.feature).

  Skips when the dataAccessAudit flag is off (the endpoint then reads Ranger's ORC audit files
  in the storage bucket, which this test does not cover) and when the shared compute is on a
  remote data plane (not run there yet). Run so far with arrowFlightForDbExplorer on, where
  iom-cluster reads the table through Arrow Flight; its Spark-session path (flag off) is not
  run yet.

  Not tested here (covered by iom-cluster's own tests): the endpoint's filters and errors.

  Background:
    * url baseUrl
    * if (!dataAccessAuditEnabled) karate.log('dataAccessAudit is off, the audit endpoint reads Ranger\'s ORC files instead, skipping')
    * if (!dataAccessAuditEnabled) karate.abort()

    * def data = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def compute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * if (isRemotePlane(compute.computeDataPlane)) karate.log('shared compute is on a remote data plane, audit there is not verified yet, skipping')
    * if (isRemotePlane(compute.computeDataPlane)) karate.abort()
    * karate.callSingle('classpath:iomete/tests/audit/setup/audit-table.feature', { domain: domain })
    * def namespace = data.database.split('.')[1]

  Scenario: a read of a table is listed in the audit log
    # Step 1: create a table only this attempt reads, then read it. Its name is random per
    # attempt, so neither another run nor a repeat of this one (same run id, compute and
    # database) can produce the audit row this step waits for, with no clock involved.
    * def queryFeature = queryFeatureFor(compute.computeDataPlane)
    * def run = function(statement) { karate.call(queryFeature, { domain: domain, computeName: compute.computeName, statement: statement }) }
    * def probe = 'audit_probe_' + (Java.type('java.util.UUID').randomUUID() + '').replace(/-/g, '').substring(0, 12)
    * def probeTable = data.database + '.' + probe
    * configure afterScenario = function() { run('DROP TABLE IF EXISTS ' + probeTable) }
    * run('CREATE TABLE ' + probeTable + ' (x INT)')
    * run('SELECT count(*) FROM ' + probeTable)

    # Step 2: the read appears in today's audit log ("today" is the server's own date). Events
    # travel through the event stream and are written in batches, so wait up to 7 minutes. The
    # all-in-one environment is slower due to single-node constraints. An empty list can also
    # mean the audit table could not be read, so the test only fails once the wait runs out.
    # A read in the last minutes before midnight can land in the next day's list and fail the
    # wait (rare).
    # The row is matched on the probe table anywhere after "<database>" in its path parts, because
    # the named fields are shifted one place today, so the shifted column
    # list holds every table one session read in that database. This passes both ways.
    * def parts = function(r) { return [r.databaseName, r.tableName].concat(r.columnNames || []) }
    * def isOurRead = function(r) { var p = parts(r); var i = p.indexOf(namespace); return r.action == 'select' && i >= 0 && p.indexOf(probe, i + 1) > i }
    # The endpoint returns at most 1000 of the day's rows from every compute, so ask only for the
    # rows from this compute's driver. Each poll logs what came back, so a timeout shows whether
    # the list stayed empty (no events recorded, or an audit table whose schema no longer matches
    # the writer) or had rows but not ours.
    * def agentHostname = 'cc-' + compute.computeName + '-driver'
    * def listAudit = function(host) { return karate.call('classpath:iomete/helpers/audit/list-audit.feature', host ? { agentHostname: host } : {}) }
    * def summary = function(rows) { return rows.map(r => [r.agentHostname, r.user, r.action, parts(r).join('.')].join(' ')).filter((s, i, all) => all.indexOf(s) == i) }
    # A JS loop rather than `retry until`, so a timeout can still look for the read in every compute's rows.
    * def waitForRead =
      """
      function() {
        var deadline = java.lang.System.currentTimeMillis() + 7 * 60 * 1000;
        var last = null;
        while (java.lang.System.currentTimeMillis() < deadline) {
          last = listAudit(agentHostname);
          karate.log('audit poll:', last.status, last.rows ? last.rows.length + ' row(s)' : 'no rows');
          var hit = last.rows ? last.rows.find(isOurRead) : null;
          if (hit) return hit;
          java.lang.Thread.sleep(10000);
        }
        if (last && last.rows) karate.log('audit rows from ' + agentHostname + ':\n' + summary(last.rows).join('\n'));
        var all = listAudit(null);
        var ours = all.rows ? all.rows.filter(r => parts(r).indexOf(probe) >= 0) : [];
        karate.log('audit rows naming ' + probe + ' from any compute (' + (all.rows ? all.rows.length : 0) + ' rows today):\n' + (ours.length ? summary(ours).join('\n') : 'none'));
        return null;
      }
      """
    * def row = waitForRead()
    * if (!row) karate.fail('the read of ' + probeTable + ' is not in the audit log of ' + agentHostname + ' after 7 min')
    * karate.log('audit row:', row)
    # accessResult 1 means the access was allowed
    And match row contains { accessResult: 1 }

    # Step 3: the row names the user who ran the query (the run's own token).
    Given path 'api/v1/user'
    When method get
    Then status 200
    And match row.user == response.username
