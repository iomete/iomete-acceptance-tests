@lock=security
Feature: Data security — a deny policy is enforced on a metastore (USING json) table

  A USING json table lives in the Hive Metastore, not the Iceberg REST catalog, so the
  catalog-side authorizer never sees it: Spark's Ranger plugin is the only enforcement
  point. Admin seeds the table and reads it back (the real HMS round trip), then
  karate-security-user runs the same SELECT and must be refused.
  Verified against dev (2026-09-29): a database created through spark_catalog is visible
  on the Hive side, so the USING json create needs no extra setup.

  Background:
    * url baseUrl
    # onboarded query-user + warm compute + seeded security database
    * def ctx = karate.callSingle('classpath:iomete/tests/data-security/setup/security-user.feature', { domain: domain })
    * def user = ctx.user
    * def database = ctx.database
    * def computeName = ctx.computeName
    * def userToken = ctx.userToken

    # scenario-owned json table, seeded from the same fixture the assertions derive from.
    # No CREATE OR REPLACE for v1 datasource tables — drop first (safe on re-runs).
    * def table = 'raw_events'
    * def fq = database + '.' + table
    * def events = read('classpath:iomete/tests/data-security/setup/data/raw_events.json')
    * def eventRows = events.map(e => "(" + e.id + ", '" + e.event + "')").join(', ')
    * def run = function(statement){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { computeName: computeName, statement: statement }).result }
    * run('DROP TABLE IF EXISTS ' + fq)
    * run('CREATE TABLE ' + fq + ' (id INT, event STRING) USING json')
    * run('INSERT INTO ' + fq + ' VALUES ' + eventRows)

    # the ADMIN creates the deny policy, not the user
    * def deny = call read('classpath:iomete/tests/data-security/setup/policies/deny-json-table-policy.feature') { user: '#(user)', database: '#(database)', table: '#(table)' }
    * def policyName = deny.policyName

    # teardown: always remove the policy and the table, pass or fail
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/security/delete-policy.feature', { kind: 'access', name: policyName });
        karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { computeName: computeName, statement: 'DROP TABLE IF EXISTS ' + fq });
      }
      """

  Scenario: karate-security-user is denied all access to the json table
    * def statement = 'SELECT event FROM ' + fq + ' ORDER BY id'

    # admin reads back the seeded rows — the HMS round trip
    * def expected = events.map(e => e.event)
    * def adminRun = call read('classpath:iomete/helpers/query/run-query-v2.feature') { computeName: '#(computeName)', statement: '#(statement)' }
    * match adminRun.result.values == expected

    # the user runs the same query, retried until the deny propagates (~10s)
    * def isDenied = function(r){ return r.status == 'FAILED' }
    * def result = call read('classpath:iomete/helpers/query/run-query-v2-as.feature') { userToken: '#(userToken)', computeName: '#(computeName)', statement: '#(statement)', predicate: '#(isDenied)', attempts: 15 }

    * match result.status == 'FAILED'
    * match result.queryResponse.errorMessage contains 'Permission denied'
    * match result.queryResponse.errorMessage contains user
    * match result.queryResponse.errorMessage contains table
