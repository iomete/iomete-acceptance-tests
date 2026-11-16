// Waits, through get_query_status, while a query MCP knows is still in one of the given statuses,
// and returns the first status outside them (or the last one read, after about 3 minutes).
// Without statuses it waits until the query has finished: iom-sql v2 holds a new query PENDING,
// then SUBMITTED, before it runs, and a cancel passes through CANCELLING.
function(domain, queryId, statuses) {
  var waitedOn = statuses || ['PENDING', 'SUBMITTED', 'RUNNING', 'CANCELLING'];
  var status;
  for (var i = 0; i < 90; i++) {
    status = karate.call('classpath:iomete/helpers/mcp/call-tool.feature', { name: 'get_query_status', args: { domain: domain, query_id: queryId } }).structuredContent.query_status.status;
    if (!waitedOn.includes(status)) return status;
    java.lang.Thread.sleep(2000);
  }
  return status;
}
