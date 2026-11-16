// The iom-sql version MCP sends a new query to, read the way MCP reads it: 'sql-v2' while the
// sqlEditorV2 rollout flag is on, 'sql-v1' while it is off or not set. An admin can change the
// flag at any time, so call it right before the query is submitted, not once per run.
function(baseUrl) {
  var flags = karate.call('classpath:iomete/helpers/settings/rollout-flags.feature', { baseUrl: baseUrl }).flags;
  return flags.sqlEditorV2 == true ? 'sql-v2' : 'sql-v1';
}
