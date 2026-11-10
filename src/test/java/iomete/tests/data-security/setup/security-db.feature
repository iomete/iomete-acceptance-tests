@ignore
Feature: Seed the security test database — invoked once per run via karate.callSingle.
  Rebuilds this run's security database from the fixtures in setup/data/ so security
  scenarios have deterministic tables to attach policies to. CREATE OR REPLACE makes this
  idempotent, even after a half-finished previous run. Tables are shaped for the three
  spark-security scenario families:
    customers  — column masking (email, phone, ssn) and row-level filtering (region, country, tier)
    salaries   — a whole-table access-deny target
  Tests derive their expected values from the same fixtures, so data and assertions cannot drift.
  Returns: computeName, database, customers, salaries.

  Scenario: create the security database and rebuild its tables from fixtures
    * def compute = karate.callSingle('classpath:iomete/tests/data-security/setup/security-compute.feature', { domain: domain })
    * def computeName = compute.computeName
    * def database = fixtures.securityDb

    * def customers = read('classpath:iomete/tests/data-security/setup/data/customers.json')
    * def customerRows = customers.map(c => "(" + c.id + ", '" + c.full_name + "', '" + c.email + "', '" + c.phone + "', '" + c.ssn + "', '" + c.country + "', '" + c.region + "', '" + c.tier + "')").join(', ')

    * def salaries = read('classpath:iomete/tests/data-security/setup/data/salaries.json')
    * def salaryRows = salaries.map(s => "(" + s.customer_id + ", " + s.base_salary + ", " + s.bonus + ")").join(', ')

    # v1 cannot reach a compute on a remote data plane, so seeding follows the compute's plane
    * def queryFeature = queryFeatureFor(compute.computeDataPlane)
    * def run = function(statement){ karate.call(queryFeature, { domain: domain, computeName: computeName, statement: statement }) }
    * run('CREATE DATABASE IF NOT EXISTS ' + database)

    * run('CREATE OR REPLACE TABLE ' + database + '.customers (id INT, full_name STRING, email STRING, phone STRING, ssn STRING, country STRING, region STRING, tier STRING)')
    * run('INSERT INTO ' + database + '.customers VALUES ' + customerRows)

    * run('CREATE OR REPLACE TABLE ' + database + '.salaries (customer_id INT, base_salary DOUBLE, bonus DOUBLE)')
    * run('INSERT INTO ' + database + '.salaries VALUES ' + salaryRows)
