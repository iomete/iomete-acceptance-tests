@ignore
Feature: Reset the Event Stream test database — invoked once per run via karate.callSingle.
  Ensures this run's database exists and is empty, so every run starts clean.
  Returns: database, computeName.

  Iceberg has uuid, time and fixed, but Spark SQL has no syntax for any of them — CREATE TABLE
  fails with UNSUPPORTED_DATATYPE. Tables are created through SQL the way users create them, so
  those three have no end-to-end path to test.

  Scenario: drop this run's event-stream tables, then recreate them
    * def compute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = compute.computeName
    * def database = fixtures.eventStreamDb

    * def run = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: statement }).result }
    * run('CREATE DATABASE IF NOT EXISTS ' + database)

    # Same one-by-one drop as tests/sql/setup/ddl-db.feature: DROP DATABASE ... CASCADE reports
    # COMPLETED but leaves the member tables behind in this catalog.
    * def existing = run('SHOW TABLES IN ' + database)
    * def dropEach = function(rows){ for (var i = 1; i < rows.length; i += 3) run('DROP TABLE IF EXISTS ' + database + '.' + rows[i]) }
    * dropEach(existing.values || [])

    # Primitives and date/time.
    * def primitives = database + '.primitives'
    * run('CREATE TABLE ' + primitives + ' (flag boolean, i int, l bigint, f float, d double, s string, small_dec decimal(10,5), dt date, ts timestamp) USING iceberg')

    # Nested types, including a struct in a list and a struct in a struct.
    * def complex = database + '.complex'
    * run('CREATE TABLE ' + complex + ' (id int, addr struct<street: string, city: string, zip: string>, tags array<string>, counts map<string, bigint>, items array<struct<name: string, qty: int>>, deep struct<outer: struct<inner: string>>) USING iceberg')

    # A string and an int column left out of the event, to prove they land as NULL.
    * def nullable = database + '.nullable'
    * run('CREATE TABLE ' + nullable + ' (id int, maybe_s string, maybe_i int) USING iceberg')

    # One narrow table for the batch case, so a thousand rows do not crowd the others.
    * def batch = database + '.batch'
    * run('CREATE TABLE ' + batch + ' (seq int, label string) USING iceberg')
