// Compares a tools/list result against a baseline the way an OpenAPI compatibility check
// compares request bodies: a schema change that rejects a call an agent already makes, or
// that this diff cannot classify, is breaking; anything else is only noted. Descriptions are ignored.
function(baseline, live) {
  const breaking = [];
  const notes = [];
  const lower = ['minimum', 'minLength', 'minItems'];
  const upper = ['maximum', 'maxLength', 'maxItems'];
  const checked = ['type', 'description', 'default', 'enum', 'items', 'properties', 'required', 'additionalProperties'].concat(lower, upper);

  function compare(path, before, after) {
    if (JSON.stringify(before.type) != JSON.stringify(after.type)) breaking.push(path + ': type ' + JSON.stringify(before.type) + ' -> ' + JSON.stringify(after.type));
    lower.forEach(k => {
      if (after[k] != null && (before[k] == null || after[k] > before[k])) breaking.push(path + ': ' + k + ' raised to ' + after[k]);
    });
    upper.forEach(k => {
      if (after[k] != null && (before[k] == null || after[k] < before[k])) breaking.push(path + ': ' + k + ' lowered to ' + after[k]);
    });
    if (after.enum) {
      (before.enum || []).filter(v => after.enum.indexOf(v) < 0).forEach(v => breaking.push(path + ': enum value ' + v + ' removed'));
      if (!before.enum) breaking.push(path + ': now restricted to ' + after.enum);
    }
    if (JSON.stringify(before.default) != JSON.stringify(after.default)) notes.push(path + ': default ' + JSON.stringify(before.default) + ' -> ' + JSON.stringify(after.default));
    if (before.items && after.items) compare(path + '[]', before.items, after.items);
    if (after.items && !before.items) breaking.push(path + ': items now restricted');
    Object.keys(Object.assign({}, before, after))
      .filter(k => checked.indexOf(k) < 0 && JSON.stringify(before[k]) != JSON.stringify(after[k]))
      .forEach(k => breaking.push(path + ': ' + k + ' changed, not checked by this diff'));
    if (before.type != 'object') return;

    // with additionalProperties false a removed argument is rejected, not ignored
    if (before.additionalProperties !== false && after.additionalProperties === false) breaking.push(path + ': no longer accepts extra properties');
    const was = before.properties || {};
    const now = after.properties || {};
    const wasRequired = before.required || [];
    const nowRequired = after.required || [];
    Object.keys(was).forEach(p => {
      if (!now[p]) breaking.push(path + '.' + p + ': removed');
      else compare(path + '.' + p, was[p], now[p]);
    });
    nowRequired.filter(p => wasRequired.indexOf(p) < 0).forEach(p => breaking.push(path + '.' + p + ': now required'));
    Object.keys(now).filter(p => !was[p] && nowRequired.indexOf(p) < 0).forEach(p => notes.push(path + '.' + p + ': optional argument added'));
  }

  baseline.forEach(tool => {
    const current = live.find(t => t.name == tool.name);
    if (!current) breaking.push(tool.name + ': tool removed');
    else compare(tool.name, tool.inputSchema, current.inputSchema);
  });
  live.filter(t => !baseline.some(b => b.name == t.name)).forEach(t => notes.push(t.name + ': tool added'));
  return { breaking: breaking, notes: notes };
}
