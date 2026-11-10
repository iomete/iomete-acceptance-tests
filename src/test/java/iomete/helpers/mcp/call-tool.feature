@ignore
Feature: Call the platform's MCP server once and decode its reply (plumbing).
  The server speaks JSON-RPC 2.0 over Streamable HTTP, statelessly: one POST per call, no
  initialize first. It always answers as Server-Sent Events, and the reply is the event whose
  message carries this request's id. Runs as the suite's admin token, like any other request.
  The official Java MCP client could speak the protocol instead, the way helpers/connection/ runs
  JDBC, but it adds a dependency, picks the protocol version itself, and its calls stay out of
  Karate's request log, which the report and the Backstage API coverage view read. Call it with:
    karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: 'whoami', args: {} })
    karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { method: 'tools/list' })
  Fails the caller on a JSON-RPC error or a tool error (result.isError), unless allowToolError is true.
  Returns:
    result             the JSON-RPC result
    structuredContent  the tool's answer (tools/call only)

  Scenario: post one JSON-RPC message and decode the SSE reply
    * def rpcMethod = karate.get('method', 'tools/call')
    * def params = rpcMethod == 'tools/call' ? { name: name, arguments: karate.get('args', {}) } : null
    * def requestId = 1

    Given url mcpBaseUrl
    And path 'mcp'
    # the server answers 400 unless the client accepts both, although it only ever sends SSE
    And header Accept = 'application/json, text/event-stream'
    # the oldest revision with structured tool output, which the tests read;
    # 2026-07-28 would also need Mcp-Method/Mcp-Name headers and _meta on every call
    And header MCP-Protocol-Version = '2025-06-18'
    And request { jsonrpc: '2.0', id: '#(requestId)', method: '#(rpcMethod)', params: '##(params)' }
    When method post
    Then status 200

    # a notification can come before the reply
    * def eventMessages = read('classpath:iomete/helpers/mcp/event-stream-messages.js')
    * def message = eventMessages(response).find(m => m.id == requestId)
    * if (!message) karate.fail('MCP ' + rpcMethod + ': no reply with id ' + requestId + ' in the event stream: ' + response)
    * if (message.error) karate.fail('MCP ' + rpcMethod + ' failed: ' + JSON.stringify(message.error))
    * def result = message.result
    * if (result.isError && !karate.get('allowToolError', false)) karate.fail('MCP ' + name + ' returned an error: ' + JSON.stringify(result.structuredContent))
    * def structuredContent = result.structuredContent
