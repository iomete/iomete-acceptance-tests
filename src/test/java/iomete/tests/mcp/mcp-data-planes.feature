@lock=sql
Feature: MCP server - an agent sees which data plane each compute runs on

  The server runs on the control plane and lists computes on every data plane. Its query tools
  still go through iom-sql v1, which cannot reach a compute on a remote plane, so an agent has
  to see each compute's plane before it picks one. With IOMETE_DATA_PLANE_STRATEGY=external the
  shared SQL compute lands on a remote plane, so the same scenario covers that case.

  Background:
    * url baseUrl
    * if (!platformAtLeast('4.0.3')) { karate.log('data_plane ships from 4.0.3, skipping on ' + platformVersion); karate.abort() }
    # MCP is off by default for customers
    * if (!mcpServerEnabled) { karate.log('MCP is off on this environment, skipping'); karate.abort() }
    Given url mcpBaseUrl
    And path 'mcp', 'version'
    When method get
    Then status 200
    And match response.service == 'iom-mcp-server'
    * url baseUrl

  Scenario: list_compute_clusters shows the data plane the platform reports for each compute
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def listed = karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: 'list_compute_clusters', args: { domain: domain } }).structuredContent
    * match listed.compute_clusters[*].id contains sqlCompute.computeId

    Given path 'api/v2/domains', domain, 'compute'
    When method get
    Then status 200
    * def apiItems = response.items
    * def apiPlaneOf = function(id){ var item = apiItems.find(x => x.id == id); return item && item.dataPlane ? item.dataPlane : null }
    * def mismatches = listed.compute_clusters.map(c => ({ id: c.id, mcp: c.data_plane || null, api: apiPlaneOf(c.id) })).filter(m => m.mcp != m.api)
    * match mismatches == []
