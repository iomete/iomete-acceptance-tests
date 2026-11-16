@lock=sql
Feature: MCP server - new queries go to the iom-sql version the sqlEditorV2 flag names

  run_query, explain_query, sample_table and execute_column_profile send a new query to iom-sql v2
  while the platform's sqlEditorV2 rollout flag is on, and to v1 while it is off or not set, and
  name the version as backend. The console, Query Monitoring and Table Maintenance follow the same
  flag, so a query MCP sends elsewhere is missing where admins look for it. The flag is read here
  the way MCP reads it, and the query must read back on the same version through get_query_status
  and get_query_result. A run covers whichever value the target has; the other value needs the
  flag set the other way, on this target or another.

  Background:
    * url baseUrl
    # builds from main always run it; set to the first release that sends new queries by the flag
    * def submitByFlagRelease = '4.1.0'
    * if (!platformAtLeast(submitByFlagRelease)) { karate.log('MCP sends new queries by the sqlEditorV2 flag from ' + submitByFlagRelease + ', skipping on ' + platformVersion); karate.abort() }
    # MCP is off by default for customers
    * if (!mcpServerEnabled) { karate.log('MCP is off on this environment, skipping'); karate.abort() }
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def callTool = function(name, args, allowToolError){ return karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: name, args: args, allowToolError: !!allowToolError }) }
    * def submitBackend = read('classpath:iomete/helpers/mcp/submit-backend.js')

  Scenario: run_query submits where sqlEditorV2 points, and the query reads back on that version
    * def expected = submitBackend(baseUrl)
    * karate.log('sqlEditorV2 says new queries go to', expected)
    # v1 only reaches a compute on the local plane; v2 goes through the plane's own listener, so it runs there too
    * if (expected == 'sql-v1' && isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('compute is on a remote plane, which sql-v1 cannot reach, skipping'); karate.abort() }

    # one row, with the row limits sent: left out they default to 100, which an install with a lower row cap refuses
    * def run = callTool('run_query', { domain: domain, compute_cluster: sqlCompute.computeName, sql: 'SELECT 1 AS id', inline_row_limit: 1 }, true)
    # an error still names the version it was sent to, which is what this checks first
    * if (run.result.isError) karate.fail('run_query on ' + (run.structuredContent.details || {}).backend + ' (expected ' + expected + ') returned an error: ' + JSON.stringify(run.structuredContent))
    * def query = run.structuredContent.value
    * match query.query_id == '#string'
    * match query.backend == expected

    # run_query returns once its inline wait ends, which can be before the query has finished
    * def waitFinished = read('classpath:iomete/helpers/mcp/wait-query-finished.js')
    * match waitFinished(domain, query.query_id) == 'COMPLETED'
    * def status = callTool('get_query_status', { domain: domain, query_id: query.query_id }).structuredContent
    * match status.backend == expected
    * match status.query_status contains { query_id: '#(query.query_id)', status: 'COMPLETED' }

    * def result = callTool('get_query_result', { domain: domain, query_id: query.query_id, limit: 1 }).structuredContent.value
    * match result.backend == expected
    * def ids = result.query_result.rows.map(r => Number(r.id))
    * match ids == [1]
