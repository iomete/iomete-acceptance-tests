@lock=sql
Feature: MCP server - cancel_query against a live iom-sql

  cancel_query reports cancelled: true only when iom-sql answers the cancel with CANCELLED, and
  a query that already finished is reported as such, with no cancel sent and no hash asked for.
  The server's own tests answer the cancel with fakes, so this pins what iom-sql really replies,
  on the version run_query submitted to, through the gateway, as the suite's admin.

  Background:
    * url baseUrl
    # cancel_query's cancelled field and its replies ship from 4.0.2
    * if (!platformAtLeast('4.0.2')) { karate.log('cancel_query as pinned here ships from 4.0.2, skipping on ' + platformVersion); karate.abort() }
    # MCP is off by default for customers
    * if (!mcpServerEnabled) { karate.log('MCP is off on this environment, skipping'); karate.abort() }
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    # with sqlEditorV2 off MCP submits through the v1 SQL API, which only reaches a compute on the local plane;
    # with it on the query goes to v2, which has not been run on a remote plane for this scenario
    * if (isRemotePlane(sqlCompute.computeDataPlane)) { karate.log('compute is on a remote plane, skipping'); karate.abort() }
    # from 4.1.0 run_query submits where sqlEditorV2 points (read just before each scenario submits), and status and
    # cancel find the query there; backend ships from 4.1.0, builds from main always have it
    * def submitBackend = platformAtLeast('4.1.0') ? read('classpath:iomete/helpers/mcp/submit-backend.js')(baseUrl) : '##string'
    # v2 holds a new query PENDING, then SUBMITTED, before it runs
    * def active = ['PENDING', 'SUBMITTED', 'RUNNING', 'CANCELLING']
    * def callTool = function(name, args, allowToolError){ return karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: name, args: args, allowToolError: !!allowToolError }) }
    * def runQuery = function(sql){ return callTool('run_query', { domain: domain, compute_cluster: sqlCompute.computeName, sql: sql }).structuredContent.value }
    * def statusOf = function(queryId){ return callTool('get_query_status', { domain: domain, query_id: queryId }).structuredContent.query_status.status }
    # run_query returns once its inline wait ends, so even a SELECT 1 can come back RUNNING
    * def waitWhile = read('classpath:iomete/helpers/mcp/wait-query-finished.js')
    # with several iom-sql replicas a confirmed cancel can reach one not holding the query and come back RUNNING, so it is sent again
    * def unconfirmed = function(reply){ return !reply.isError && reply.cancelled === false && reply.query_status && reply.query_status.status == 'RUNNING' }
    * def confirmedCancel = function(queryId, hash, attempts){ var reply; for (var i = 0; i < attempts; i++) { var c = callTool('cancel_query', { domain: domain, query_id: queryId, confirmed_cancellation_hash: hash }, true); reply = karate.merge(c.structuredContent, { isError: !!c.result.isError }); if (!unconfirmed(reply)) return reply; java.lang.Thread.sleep(1000) } return reply }
    # stops a query a failed step left running on the shared SQL compute, and logs it when the cancel is never confirmed.
    # On v2 it goes through the V2 API until the query is no longer active: cancel_query sends no cancel for a query
    # still PENDING, which would then start after the lane is released
    * def cancelLeftover = function(queryId, backend){ if (!queryId) return; if (backend == 'sql-v2') { karate.call('classpath:iomete/helpers/query/cancel-query-v2.feature', { domain: domain, queryId: queryId }); return } if (!active.includes(statusOf(queryId))) return; var d = callTool('cancel_query', { domain: domain, query_id: queryId }, true).structuredContent; var h = d && d.details && d.details.confirmed_cancellation_hash; var reply = h ? confirmedCancel(queryId, h, 15) : d; if (reply && reply.cancelled === true) return; if (active.includes(statusOf(queryId))) karate.log('cleanup could not cancel query', queryId, '- it may still be running:', JSON.stringify(reply)) }

  Scenario: a running query is cancelled once the user confirms the hash
    # a shuffle over far more rows than the compute gets through before the cancel
    * def run = callTool('run_query', { domain: domain, compute_cluster: sqlCompute.computeName, sql: 'SELECT id % 1000 AS k, count(*) AS n FROM range(0, 50000000000) GROUP BY k' }, true)
    # registered before any assertion: an error.execution still names a submitted query
    * def queryId = run.result.isError ? (run.structuredContent.details || {}).query_id : run.structuredContent.value.query_id
    # the version the reply names, and the flag's where the reply names none
    * def queryBackend = (run.result.isError ? (run.structuredContent.details || {}).backend : run.structuredContent.value.backend) || submitBackend
    * configure afterScenario = function(){ cancelLeftover(queryId, queryBackend) }
    * if (run.result.isError) karate.fail('run_query returned an error: ' + JSON.stringify(run.structuredContent))
    * def query = run.structuredContent.value
    * match query.query_id == '#string'
    * match query.backend == submitBackend
    # v2 can still hold it PENDING or SUBMITTED when run_query returns, so it is waited into RUNNING
    * def startingStatuses = submitBackend == 'sql-v2' ? ['PENDING', 'SUBMITTED', 'RUNNING'] : ['RUNNING']
    * match startingStatuses contains query.query_status
    * match waitWhile(domain, query.query_id, ['PENDING', 'SUBMITTED']) == 'RUNNING'
    * def cancelArgs = { domain: '#(domain)', query_id: '#(query.query_id)' }

    # the first call asks for the user's approval and hands over the hash
    * def deny = callTool('cancel_query', cancelArgs, true)
    * match deny.result.isError == true
    * match deny.structuredContent contains { code: 'denied.confirmation_required' }
    * match deny.structuredContent.details.confirmed_cancellation_hash == '#string'
    * match deny.structuredContent.details.query_status.status == 'RUNNING'

    # v2 writes CANCELLED in the cancel itself, so there one confirmed call must do it
    * def cancel = confirmedCancel(query.query_id, deny.structuredContent.details.confirmed_cancellation_hash, submitBackend == 'sql-v2' ? 1 : 5)
    * match cancel.isError == false
    * match cancel contains { cancelled: true, query_id: '#(query.query_id)' }
    * match cancel.backend == submitBackend
    * match cancel.query_status contains { status: 'CANCELLED' }

    # the final status comes from get_query_status
    * match waitWhile(domain, query.query_id) == 'CANCELLED'

  Scenario: a finished query is reported as already finished, without a hash
    * def query = runQuery('SELECT 1')
    * match query.query_id == '#string'
    * match waitWhile(domain, query.query_id) == 'COMPLETED'

    * def cancel = callTool('cancel_query', { domain: domain, query_id: query.query_id }).structuredContent
    * match cancel.cancelled == false
    * match cancel.backend == submitBackend
    * match cancel.query_status contains { status: 'COMPLETED' }
    * match cancel.cancellation_plan == '#notpresent'
