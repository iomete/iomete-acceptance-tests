@ignore
Feature: Seed deterministic test data — invoked once per run via karate.callSingle.
  Tests must not assume any pre-existing data on dev: this rebuilds the karate test
  database from the fixtures in setup/data/ on every run (CREATE OR REPLACE makes it
  idempotent, even after a half-finished previous run). Tests derive their expected
  values from the same fixtures, so data and assertions cannot drift apart.
  Returns: computeName, database, employees.

  Scenario: create the test database and rebuild its tables from fixtures
    * def compute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def computeName = compute.computeName
    * def database = fixtures.db

    * def employees = read('classpath:iomete/tests/sql/setup/data/employees.json')
    * def employeeRows = employees.map(e => '(' + e.id + ", '" + e.name + "', " + e.salary + ')').join(', ')

    # v1 cannot reach a compute on a remote data plane, so seeding follows the compute's plane
    * def queryFeature = queryFeatureFor(compute.computeDataPlane)
    * def run = function(statement){ karate.call(queryFeature, { domain: domain, computeName: computeName, statement: statement }) }
    * run('CREATE DATABASE IF NOT EXISTS ' + database)
    * run('CREATE OR REPLACE TABLE ' + database + '.employees (id INT, name STRING, salary DOUBLE)')
    * run('INSERT INTO ' + database + '.employees VALUES ' + employeeRows)