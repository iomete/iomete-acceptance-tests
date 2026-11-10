@ignore
Feature: Reset the DDL test database — invoked once per run via karate.callSingle.
  Ensures this run's ddl database exists and is empty, so every run starts clean
  and dev never accumulates tables. Called from the query-ddl Background, so the reset
  is guaranteed before any scenario — no ordering assumption. Returns: database.

  Note: DROP DATABASE ... CASCADE is broken in this catalog — it returns COMPLETED but
  leaves the member table rows behind (verified against dev). Explicit DROP TABLE does
  work, so we list the tables and drop them one by one instead.

  Scenario: drop the ddl test database's tables one by one, keep the database
    * def compute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = compute.computeName
    * def database = fixtures.ddlDb

    * def run = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: statement }).result }
    * run('CREATE DATABASE IF NOT EXISTS ' + database)

    # SHOW TABLES returns rows flattened as [namespace, tableName, isTemporary, ...];
    # the table name is every 3rd value starting at index 1.
    * def existing = run('SHOW TABLES IN ' + database)
    * def dropEach = function(rows){ for (var i = 1; i < rows.length; i += 3) run('DROP TABLE IF EXISTS ' + database + '.' + rows[i]) }
    * dropEach(existing.values || [])