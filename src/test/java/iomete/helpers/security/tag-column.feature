@ignore
Feature: Admin action — tag or untag a column through a classification change request.
  Tags only reach a column through a change request that an admin approves, and approving
  applies it straight away. Does nothing when the column is already in the wanted state, so
  a retry and teardown can always call it:
    karate.call('classpath:iomete/helpers/security/tag-column.feature',
                { tagId: t, tagName: n, database: 'spark_catalog.karate_security_db_x',
                  table: 'customers', column: 'phone', requestType: 'ADD' })
  requestType is ADD or REMOVE.

  Scenario: file the change request and approve it, unless it is already applied
    Given url baseUrl
    And path 'api/v1/admin/governance/classification-tags', tagId, 'assets'
    When method get
    Then status 200
    * def assets = Array.isArray(response) ? response : response.items
    * def tagged = assets.some(a => a.tableName == table && a.columnName == column)
    * if (tagged == (requestType == 'ADD')) karate.abort()

    # the fixture database is catalog-qualified, the change request takes the two apart
    * def parts = database.split('.')
    Given url baseUrl
    And path 'api/v1/domains', domain, 'governance/classification-requests'
    And request { catalogName: '#(parts[0])', schemaName: '#(parts[1])', tableName: '#(table)', columnName: '#(column)', tagName: '#(tagName)', requestType: '#(requestType)' }
    When method post
    Then status 201

    Given url baseUrl
    And path 'api/v1/admin/governance/classification-requests', response.id, 'review'
    And request { status: 'APPROVED' }
    When method put
    Then status 200
