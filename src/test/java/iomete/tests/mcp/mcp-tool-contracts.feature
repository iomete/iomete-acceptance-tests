@lock=sql
Feature: MCP server - the tool contract customers' agents are written against

  Agents call MCP tools by name, with the arguments they were built for, and on-prem installs
  upgrade a few releases at a time. A renamed tool or a newly required argument breaks those
  agents on upgrade, and a platform change under a tool breaks what it answers. This checks
  the deployed server through the gateway, as the suite's admin:
  - tools/list stays backward compatible with setup/data/tools-baseline.json, the way an
    OpenAPI compatibility check guards a REST API (rules in helpers/mcp/breaking-changes.js).
    It lives here, not in the server's tests, so a server change cannot update its own
    baseline in the same pull request.
  - a query runs through run_query and pages through get_query_result, so the platform side
    (iom-sql v1 and a live compute) still answers in the shape the tools promise.

  Background:
    * url baseUrl
    * if (!platformAtLeast('4.0.0')) { karate.log('MCP ships from 4.0.0, skipping on ' + platformVersion); karate.abort() }
    # MCP is off by default for customers
    * if (!mcpServerEnabled) { karate.log('MCP is off on this environment, skipping'); karate.abort() }
    # the flag turns on the server and its /mcp route together, so a wrong answer here is a fault
    Given url mcpBaseUrl
    And path 'mcp', 'version'
    When method get
    Then status 200
    And match response.service == 'iom-mcp-server'
    * url baseUrl

  Scenario: tools/list stays backward compatible with the baseline
    * def toolsListResponse = call read('classpath:iomete/helpers/mcp/call-tool.feature') { method: 'tools/list' }
    # the diff reads one page, so a paged list fails here instead of as removed tools
    * match toolsListResponse.result.nextCursor == '#notpresent'
    * def compare = read('classpath:iomete/helpers/mcp/breaking-changes.js')
    * def diff = compare(read('classpath:iomete/tests/mcp/setup/data/tools-baseline.json'),toolsListResponse.result.tools)
    * karate.log('non-breaking tool changes:', diff.notes)
    * match diff.breaking == []

  Scenario: a query runs through run_query and pages through get_query_result
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    # with sqlEditorV2 off MCP submits through the v1 SQL API, which only reaches a compute on the local plane;
    # with it on the query goes to v2, which has not been run on a remote plane for this scenario
    * if (isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('compute is on a remote plane, skipping'); karate.abort() }
    * def data = karate.callSingle('classpath:iomete/tests/sql/setup/test-data.feature', { domain: domain })
    * def employees = data.employees
    * def callTool = function(name, args){ return karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: name, args: args }) }
    * def typed = function(rows){ return rows.map(r => ({ id: Number(r.id), name: r.name, salary: Number(r.salary) })) }

    # the LIMIT is what makes all four rows pageable; without it only inline_row_limit + 1 are stored
    * def sql = 'SELECT * FROM ' + data.database + '.employees ORDER BY id LIMIT 10'
    # from 4.1.0 run_query submits where sqlEditorV2 points (read just before the submit), and the read finds the query there;
    # backend ships from 4.1.0, builds from main always have it
    * def submitBackend = platformAtLeast('4.1.0') ? read('classpath:iomete/helpers/mcp/submit-backend.js')(baseUrl) : '##string'
    * def runQueryRequest = { domain: '#(domain)', compute_cluster: '#(sqlCompute.computeName)', sql: '#(sql)', inline_row_limit: 2 }
    * def runQueryResponse = callTool('run_query', runQueryRequest)
    * match JSON.parse(runQueryResponse.result.content[0].text) == runQueryResponse.structuredContent
    * def query = runQueryResponse.structuredContent.value
    # run_query returns once its inline wait ends. On v2, which holds a new query before it runs, that can be before the
    # query completed: the inline rows are then not there to check, and the pages below carry the scenario. On v1 the
    # reply must be COMPLETED, as before
    * def inline = query.query_status == 'COMPLETED'
    * if (!inline && submitBackend != 'sql-v2') karate.fail('run_query answered ' + query.query_status + ' on v1, where this scenario expects the inline result of a completed query')
    * if (!inline) karate.log('run_query returned', query.query_status, 'before the query completed, so its inline rows are not checked')
    * match runQueryResponse.structuredContent contains deep { type: 'tool_result', links: '#array', meta: { trace_id: '#string', truncated: '#(inline)', risk: '#string' } }
    * match query contains { query_id: '#string', domain_source: 'argument', compute_cluster_source: 'argument' }
    # a failed query is a tool error, never a reply, so any other status here is a broken reply
    * match ['COMPLETED', 'PENDING', 'SUBMITTED', 'RUNNING'] contains query.query_status
    * match query.resolved_domain.id == domain
    * match query.resolved_compute_cluster.name == sqlCompute.computeName
    * def inlineResult = inline ? query.query_result : null
    * if (inline && !(inlineResult.truncated === true && inlineResult.returned_row_count == 2)) karate.fail('run_query inline result is not 2 rows marked truncated: ' + JSON.stringify(inlineResult))
    * def inlineRows = inline ? karate.match(typed(inlineResult.rows), employees.slice(0, 2)) : { pass: true }
    * if (!inlineRows.pass) karate.fail('run_query inline rows: ' + inlineRows.message)
    * def waitFinished = read('classpath:iomete/helpers/mcp/wait-query-finished.js')
    * def finalStatus = inline ? 'COMPLETED' : waitFinished(domain, query.query_id)
    * match finalStatus == 'COMPLETED'

    # cursor is sent only when there is one: the schema types it as a string, and null is not one
    * def getQueryResult = function(cursor){ const getQueryResultRequest = { domain: domain, query_id: query.query_id, limit: 2 }; if (cursor) getQueryResultRequest.cursor = cursor; return callTool('get_query_result', getQueryResultRequest) }
    * def firstPageResponse = getQueryResult(null)
    * def firstPage = firstPageResponse.structuredContent.value
    * def secondPageResponse = getQueryResult(firstPage.pagination.next_cursor)
    * def secondPage = secondPageResponse.structuredContent.value
    # on v1 every cell comes back as a string, whatever the column type; v2 keeps a number a number
    * def rowShape = submitBackend == 'sql-v2' ? { id: '#number', name: '#string', salary: '#number' } : { id: '#string', name: '#string', salary: '#string' }
    * match each firstPage.query_result.rows == rowShape
    * match typed(firstPage.query_result.rows) == employees.slice(0, 2)
    * match firstPage.query_status contains { status: 'COMPLETED', stored_row_count: '#(employees.length)' }
    * match firstPage.pagination.next_cursor == '#string'
    * match firstPage.backend == submitBackend
    * match secondPage.backend == submitBackend
    # more rows show only as next_cursor; truncated means content was cut that no page returns
    * match firstPage.query_result.truncated == false
    * match typed(secondPage.query_result.rows) == employees.slice(2, 4)
    * match secondPage.pagination.next_cursor == '#notpresent'
