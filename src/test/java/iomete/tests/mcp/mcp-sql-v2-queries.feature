@lock=sql
Feature: MCP server - reading and cancelling queries that live on iom-sql v2

  A query lives on either iom-sql v1 or v2. get_query_status, get_query_result and cancel_query
  look it up on v2 first, fall back to v1 when v2 does not know it, and name the version that
  answered as backend. These queries are submitted through the V2 SQL API directly, the way the
  console does, so the scenarios run whichever API MCP itself submits to. The server's own tests
  answer v2 with fakes, so this is where v2's real replies are checked, through the gateway, as
  the suite's admin.

  Background:
    * url baseUrl
    # builds from main always run it; set to the first release that carries the v2 reads
    * def v2ReadsRelease = '4.1.0'
    * if (!platformAtLeast(v2ReadsRelease)) { karate.log('MCP reads iom-sql v2 queries from ' + v2ReadsRelease + ', skipping on ' + platformVersion); karate.abort() }
    # MCP is off by default for customers
    * if (!mcpServerEnabled) { karate.log('MCP is off on this environment, skipping'); karate.abort() }
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def callTool = function(name, args, allowToolError){ return karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: name, args: args, allowToolError: !!allowToolError }) }
    # limit is how many rows v2 stores (100 when not sent); queryId is optional, iom-sql makes one when it is not sent
    * def submitV2 = function(sql, limit, queryId){ return karate.call('classpath:iomete/helpers/query/submit-query-v2.feature', { domain: domain, statement: sql, computeName: sqlCompute.computeName, limit: limit, queryId: queryId || null }).queryId }
    * def statusReply = function(queryId){ return callTool('get_query_status', { domain: domain, query_id: queryId }).structuredContent }
    # v2 holds a new query PENDING, then SUBMITTED, before it runs
    * def waitWhile = function(queryId, statuses){ var s; for (var i = 0; i < 60; i++) { s = statusReply(queryId).query_status.status; if (!statuses.includes(s)) return s; java.lang.Thread.sleep(2000) } return s }
    * def waitFinished = function(queryId){ return waitWhile(queryId, ['PENDING', 'SUBMITTED', 'RUNNING', 'CANCELLING']) }

  Scenario: a finished v2 query reads back on v2 and is reported as already finished
    * def queryId = submitV2('SELECT 1', 10)
    * match waitFinished(queryId) == 'COMPLETED'

    * def status = statusReply(queryId)
    * match status.backend == 'sql-v2'
    * match status.query_status contains { query_id: '#(queryId)', status: 'COMPLETED', statement: 'SELECT 1', compute_cluster_name: '#(sqlCompute.computeName)' }

    # a finished query asks for no hash and is not an error
    * def cancel = callTool('cancel_query', { domain: domain, query_id: queryId }).structuredContent
    * match cancel contains { cancelled: false, backend: 'sql-v2' }
    * match cancel.query_status contains { status: 'COMPLETED' }
    * match cancel.cancellation_plan == '#notpresent'

  Scenario: a running v2 query is cancelled on v2 once the user confirms the hash
    # the id is chosen here and the teardown registered before the submit, so a submit whose
    # response is lost still has its query stopped on the shared SQL compute
    * def queryId = '' + java.util.UUID.randomUUID()
    * configure afterScenario = function(){ karate.call('classpath:iomete/helpers/query/cancel-query-v2.feature', { domain: domain, queryId: queryId }) }
    # a shuffle over far more rows than the compute gets through before the cancel
    * match submitV2('SELECT id % 1000 AS k, count(*) AS n FROM range(0, 50000000000) GROUP BY k', 10, queryId) == queryId
    * match waitWhile(queryId, ['PENDING', 'SUBMITTED']) == 'RUNNING'

    # the first call asks for the user's approval and hands over the hash
    * def deny = callTool('cancel_query', { domain: domain, query_id: queryId }, true)
    * match deny.result.isError == true
    * match deny.structuredContent contains { code: 'denied.confirmation_required' }
    * def hash = deny.structuredContent.details.confirmed_cancellation_hash
    * match hash == '#string'

    # one confirmed call must cancel it: v2 writes CANCELLED in the DELETE itself, so unlike v1 a
    # reply of RUNNING is a failure here, not a replica to retry on
    * def cancel = callTool('cancel_query', { domain: domain, query_id: queryId, confirmed_cancellation_hash: hash }).structuredContent
    * match cancel contains { cancelled: true, query_id: '#(queryId)', backend: 'sql-v2' }
    * match waitFinished(queryId) == 'CANCELLED'

  Scenario: get_query_result reads a v2 result of more than 100 rows up to row 100
    # v2 stores all 150 rows, but its result has no paging, so MCP reads only the first 100
    * def queryId = submitV2('SELECT id FROM range(150) ORDER BY id', 150)
    * match waitFinished(queryId) == 'COMPLETED'
    * def ids = function(page){ return page.query_result.rows.map(r => Number(r.id)) }
    * def range = function(from, to){ var out = []; for (var i = from; i < to; i++) out.push(i); return out }

    # the page size the server accepts (an install can lower its row limit), at most 40 so the walk takes several pages
    * def toolsList = call read('classpath:iomete/helpers/mcp/call-tool.feature') { method: 'tools/list' }
    * def limitSchema = toolsList.result.tools.find(t => t.name == 'get_query_result').inputSchema.properties.limit
    * def pageSize = Math.min(40, limitSchema.maximum || 40)
    # follows the cursors the server hands back: a byte budget can make a page shorter than asked
    * def walk = function(){ var pages = [], cursor = null; for (var i = 0; i < 200; i++) { var args = { domain: domain, query_id: queryId, limit: pageSize }; if (cursor) args.cursor = cursor; var page = callTool('get_query_result', args).structuredContent.value; pages.push(page); cursor = page.pagination && page.pagination.next_cursor; if (!cursor) return pages } karate.fail('get_query_result still had a next_cursor after 200 pages') }
    * def pages = walk()
    * match each pages contains { backend: 'sql-v2' }
    * def allIds = pages.map(ids).reduce((a, b) => a.concat(b), [])
    * match allIds == range(0, 100)

    # the page that ends at row 100 says the rest is left out, and offers no next page
    * def last = pages[pages.length - 1]
    * match last.query_result contains { truncated: true, truncation_reason: '#regex .*sql_v2_row_cap.*', truncation_message: '#string' }
    * match last.pagination.next_cursor == '#notpresent'
    * assert pages.length > 1
    * def first = pages[0]

    # a cursor moved past row 100 is refused, never answered with empty rows: the cursor is
    # base64url JSON with the row offset under "o". Only that number is replaced in the text: the
    # cursor also holds a uint64 request hash, which a JSON round trip turns into a BigInt
    * def Base64 = Java.type('java.util.Base64')
    * def StandardCharsets = Java.type('java.nio.charset.StandardCharsets')
    * def wire = '' + new java.lang.String(Base64.getUrlDecoder().decode(first.pagination.next_cursor), StandardCharsets.UTF_8)
    * match wire contains '"o":'
    * def pastCapWire = wire.replace(/"o":\d+/, '"o":100')
    * def pastCap = Base64.getUrlEncoder().withoutPadding().encodeToString(new java.lang.String(pastCapWire).getBytes(StandardCharsets.UTF_8))
    * def denied = callTool('get_query_result', { domain: domain, query_id: queryId, limit: pageSize, cursor: pastCap }, true)
    * match denied.result.isError == true
    * match denied.structuredContent contains { code: 'denied.invalid_input' }
    * match denied.structuredContent.details contains { reason: 'sql_v2_row_cap', backend: 'sql-v2' }
