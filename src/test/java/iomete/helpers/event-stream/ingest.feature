@ignore
Feature: POST events to an event stream's ingest endpoint (plumbing).
  karate.call('classpath:iomete/helpers/event-stream/ingest.feature',
              { ingestPath: '...', table: 'catalog.db.table', events: [ {...}, {...} ] })
  Returns: code (the HTTP status) and body, so a caller can assert on a rejection too.

  The table is named in a header, not in the path — papyrus reads `table` and looks its schema
  up in the REST catalog (main.rs). It has to be the full catalog.database.table name.

  Scenario: post the batch
    Given url baseUrl
    And path ingestPath
    And header table = table
    And request events
    When method post
    * def code = responseStatus
    * def body = response
