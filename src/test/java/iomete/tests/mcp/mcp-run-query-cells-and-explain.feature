@lock=sql
Feature: MCP server - run_query steers agents past complex cells and failed EXPLAINs

  On iom-sql v1, struct, array and map cells come back as Spark display text, not JSON, and an
  EXPLAIN that fails analysis comes back through run_query as a successful result with the error
  in its rows. run_query's description tells agents both ways out: select the fields or use
  to_json(col), and use explain_query for plans. This checks the description says so, and that
  both ways out really work against a live iom-sql, as the suite's admin, on v1 and v2 alike.

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
    * def callTool = function(name, args, allowToolError){ return karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: name, args: args, allowToolError: !!allowToolError }) }

  Scenario: run_query's description names to_json for complex cells and explain_query for plans
    # TODO: set to the first release that carries the run_query description change; builds from main always run it
    * def descriptionRelease = '4.0.3'
    * if (!platformAtLeast(descriptionRelease)) { karate.log('the run_query description steering ships from ' + descriptionRelease + ', skipping on ' + platformVersion); karate.abort() }
    * def toolsListResponse = call read('classpath:iomete/helpers/mcp/call-tool.feature') { method: 'tools/list' }
    * def runQuery = toolsListResponse.result.tools.find(t => t.name == 'run_query')
    * match runQuery.description == '#string'
    # stable substrings, not the whole sentence, so a rewording that keeps the advice passes
    * match runQuery.description contains 'to_json(col)'
    * match runQuery.description == '#regex (?is).*(struct|array|map|complex).*'
    * match runQuery.description contains 'explain_query'

  Scenario: to_json returns complex cells as JSON, and the raw cells come back as text
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    # with sqlEditorV2 off MCP submits through the v1 SQL API, which only reaches a compute on the local plane;
    # with it on the query goes to v2, which has not been run on a remote plane for this scenario
    * if (isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('compute is on a remote plane, skipping'); karate.abort() }
    * def sql = "SELECT named_struct('a', 1, 'b', 'x,y') AS s, array(1, 2) AS a, map('k', 'v') AS m, to_json(named_struct('a', 1, 'b', 'x,y')) AS s_json, to_json(array(1, 2)) AS a_json, to_json(map('k', 'v')) AS m_json"
    * def runQueryResponse = callTool('run_query', { domain: domain, compute_cluster: sqlCompute.computeName, sql: sql })
    * def query = runQueryResponse.structuredContent.value
    # run_query returns once its inline wait ends, so a slow compute can answer SUBMITTED or RUNNING; the rows then come from get_query_result
    * def waitFinished = read('classpath:iomete/helpers/mcp/wait-query-finished.js')
    * def rowsOf = function(q){ if (q.query_status == 'COMPLETED') return q.query_result.rows; var s = waitFinished(domain, q.query_id); if (s != 'COMPLETED') karate.fail('query ' + q.query_id + ' ended ' + s); return callTool('get_query_result', { domain: domain, query_id: q.query_id }).structuredContent.value.query_result.rows }
    * def rows = rowsOf(query)
    * match rows == '#[1]'
    * def row = rows[0]

    # to_json returns a string column, so the cell is JSON text whatever the result path
    * def parsed = function(cell){ return typeof cell == 'string' ? JSON.parse(cell) : cell }
    * match parsed(row.s_json) == { a: 1, b: 'x,y' }
    * match parsed(row.a_json) == [1, 2]
    * match parsed(row.m_json) == { k: 'v' }

    # the server flattens every structured cell to a string; on v1 it is Spark's display text, which is
    # only sometimes valid JSON (dates, binary and non-string map keys are not), so the text is not pinned
    * match row.s == '#string'
    * match row.a == '#string'
    * match row.m == '#string'

  Scenario: explain_query reports SQL that fails analysis as a failed query
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    # with sqlEditorV2 off MCP submits through the v1 SQL API, which only reaches a compute on the local plane;
    # with it on the query goes to v2, which has not been run on a remote plane for this scenario
    * if (isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('compute is on a remote plane, skipping'); karate.abort() }
    * def missingTable = 'spark_catalog.default.karate_missing_' + runId.replace(/[^A-Za-z0-9_]/g, '_')
    * def explainArgs = { domain: '#(domain)', compute_cluster: '#(sqlCompute.computeName)', sql: '#("SELECT * FROM " + missingTable)' }
    # the error is only reported when the plan is ready before the call returns, and a plan fetched later is not checked, so a still-running answer is asked again
    # explain_query's result has no value envelope: plan_text is top level, null while the plan is not ready
    * def stillRunning = function(e){ return !e.result.isError && e.structuredContent.plan_text === null }
    * def explainSettled = function(){ var e; for (var i = 0; i < 3; i++) { e = callTool('explain_query', explainArgs, true); if (!stillRunning(e)) return e } return e }
    * def explain = explainSettled()
    * if (stillRunning(explain)) karate.fail('explain_query plan not ready after 3 tries (query ' + explain.structuredContent.query_id + '), so whether it reports the failed EXPLAIN was not checked')
    # says what came back instead: a plan for SQL that cannot be analyzed is the fault this scenario is here for
    * if (!explain.result.isError) karate.fail('explain_query answered without an error for SQL that fails analysis: ' + redact(JSON.stringify(explain.structuredContent)).substring(0, 3000))
    * match explain.result.isError == true
    * match explain.structuredContent contains { code: 'error.query_failed', message: '#string' }
    * match explain.structuredContent.details.reason == 'explain_plan_error'
