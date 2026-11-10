@lock=api
Feature: Catalog lists through iom-cluster — the catalogs the console and policy editor load

  What this checks:
  - The domain catalog list (loaded by the console on every page) and the admin catalog list
    (loaded by the data-security policy editor) both include spark_catalog.
  - No catalog in either list exposes a plain secret: neither its access and secret keys nor a
    property with a secret-like name (password, token, secret, key).

  Both lists come from iom-core through iom-cluster, whatever the ARROW_FLIGHT_FOR_DB_EXPLORER
  flag, so this needs no compute. The database tree below a catalog is iom-sql's and is tested in
  tests/sql/schema-browser.feature.

  Not tested here (covered by iom-core's own tests): how masking works.

  Background:
    * url baseUrl
    # spark_catalog is the one catalog every environment has
    * def catalog = fixtures.db.split('.')[0]
    # Masked secrets come back as this fixed string. iom-core masks a catalog's access and secret
    # keys, and every property whose name looks secret, except token-ttl (a duration, not a secret).
    * def masked = '********'
    * def secretProperty = function(p) { return /password|token|secret|key/i.test(p.key) && !/token-ttl/i.test(p.key) }
    * def plainKeys = function(c) { return c.credentials && [c.credentials.accessKey, c.credentials.secretKey].some(v => v && v != masked) }
    * def plainProperties = function(c) { return (c.properties || []).some(p => secretProperty(p) && p.value && p.value != masked) }
    # Returns the names of catalogs that expose a plain secret; an empty list means none do.
    * def leaks = function(catalogs) { return catalogs.filter(c => plainKeys(c) || plainProperties(c)).map(c => c.name) }

  Scenario: the domain and admin catalog lists include spark_catalog and expose no plain secrets
    # Step 1: domain catalog list.
    Given path 'api/v1/domains', domain, 'schema', 'catalogs'
    When method get
    Then status 200
    And match response[*].name contains catalog
    And match leaks(response) == []

    # Step 2: admin catalog list (used by the policy editor).
    Given path 'api/v1/admin/schema/catalogs'
    When method get
    Then status 200
    And match response[*].name contains catalog
    And match leaks(response) == []
