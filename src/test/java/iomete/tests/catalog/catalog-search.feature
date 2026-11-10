@lock=sql
Feature: Data catalog search, this run's table is found through the search proxy

  The Data Catalog's search box talks to Typesense through iom-catalog's proxy, which signs
  each request with a key scoped to the catalogs the domain may see. A hit for this run's
  table proves the sync indexed it into the search backend and that the proxy, the scoped key
  and Typesense agree on what the domain is shown.

  The sync does not write to Typesense itself: a reconciler in iom-catalog polls the shared
  catalog database (every 30s by default) and imports each changed schema into this cluster's own
  index, so the first search after a sync is polled with a bounded retry.

  Background:
    * url baseUrl
    * def catalogPath = 'api/v2/domains/' + domain + '/data-catalog'
    # 501 means the catalog is not wired up here and 204 means it is. Anything else is a real
    # failure and must not pass as a skip.
    Given path catalogPath + '/enabled'
    When method get
    * if (responseStatus == 501) karate.log('data catalog is not enabled on this environment, skipping')
    * if (responseStatus == 501) karate.abort()
    Then status 204
    * def indexed = karate.callSingle('classpath:iomete/tests/catalog/setup/indexed-table.feature', { domain: domain })
    * def database = indexed.database
    * def tableName = indexed.tableName
    * def collection = 'data_assets'
    # the scoped key already restricts the catalogs; the schema filter narrows to this run's, and
    # is_deleted keeps out a document of a table a sync found gone (cleanup-run only drops the
    # Spark table; the row, and so the document, is marked deleted by the next sync)
    * def search = { q: '#(tableName)', query_by: 'name', filter_by: '#("schema:=" + database + " && is_deleted:=false")' }
    * def hasTable = function(res){ return res.hits != null && res.hits.filter(h => h.document.name == tableName).length > 0 }

  Scenario: the search proxy finds the table by name, by a single search and by a multi-search
    # the reconciler's poll interval plus one schema import, with room for a slow Typesense
    * configure retry = { count: 12, interval: 10000 }
    Given path catalogPath + '/typesense/collections/' + collection + '/documents/search'
    And params search
    And retry until responseStatus == 200 && hasTable(response)
    When method get
    Then status 200

    # the console's search box sends multi-searches, one block per collection; the same backend
    # answered once already, so this needs no poll of its own
    * def block = karate.merge(search, { collection: collection })
    Given path catalogPath + '/typesense/multi_search'
    And request { searches: ['#(block)'] }
    When method post
    Then status 200
    And match response.results[0].hits[*].document.name contains tableName
