// Explains a namespace quota or node capacity shortage in plain words, or returns null.
// Takes { subject, namespace, events, logEntries ([{ date, logLine }]), quotaRows, since }.
// Events and log lines last seen before since (epoch ms) are ignored.
// Returns { refused, giveUp, text, firstRefusalMs, lastRefusalMs }; refused is true only when the quota turned a pod away.
// giveUp is true once refusals have lasted 2 minutes and one came in the last 6 (Kubernetes reports a repeat less often over time).
function(input) {
  var now = java.lang.System.currentTimeMillis();
  var since = input.since || 0;
  var capitalise = function(s) { return s.charAt(0).toUpperCase() + s.substring(1) };
  var graceMs = 2 * 60 * 1000, stillRefusingMs = 6 * 60 * 1000;
  var toMs = function(t) { try { return t ? java.time.Instant.parse(String(t)).toEpochMilli() : 0 } catch (x) { return 0 } };
  var subject = input.subject || 'the workload';
  var namespace = input.namespace ? "namespace '" + input.namespace + "'" : 'the namespace';
  var fix = 'Stop computes, jobs or event streams you no longer need in ' + namespace + ', or ask an admin to raise its quota, then run again.';

  // every piece of evidence as { text, firstMs, ms }, oldest first, recent ones only
  // a repeated event is one series: eventTime is its first occurrence, lastObservedTime its latest
  var evidence = (input.events || []).map(e => { var last = toMs(e.lastObservedTime || e.eventTime); return { text: String(e.note || ''), firstMs: toMs(e.eventTime) || last, ms: last, event: true } })
    .concat((input.logEntries || []).map(l => ({ text: String(l.logLine || ''), firstMs: l.date || 0, ms: l.date || 0, event: false })))
    .filter(x => x.ms >= since)
    .map(x => { x.firstMs = Math.max(x.firstMs, since); return x })
    .sort((a, b) => a.ms - b.ms);

  // Kubernetes says: exceeded quota: <name>, requested: k=v,..., used: k=v,..., limited: k=v,...
  var names = { 'requests.memory': 'memory requests', 'limits.memory': 'memory limits', 'requests.cpu': 'CPU requests', 'limits.cpu': 'CPU limits', 'memory': 'memory requests', 'cpu': 'CPU requests' };
  var pairs = function(list) { var out = {}; list.replace(/,+$/, '').split(',').forEach(p => { var kv = p.split('='); if (kv.length == 2) out[kv[0].trim()] = kv[1].trim() }); return out };
  var refusals = evidence.filter(x => x.text.indexOf('exceeded quota') >= 0);
  if (refusals.length) {
    var latest = refusals[refusals.length - 1].text;
    var firstMs = Math.min.apply(null, refusals.map(x => x.firstMs)), lastMs = refusals[refusals.length - 1].ms;
    var result = { refused: true, giveUp: now - firstMs >= graceMs && now - lastMs <= stillRefusingMs, firstRefusalMs: firstMs, lastRefusalMs: lastMs };
    var m = latest.match(/exceeded quota: ([^,]+), requested: (\S+) used: (\S+) limited: (\S+)/);
    if (m) {
      var requested = pairs(m[2]), used = pairs(m[3]), limited = pairs(m[4]);
      // a requests key already says what its matching limits key would
      var keys = Object.keys(requested).filter(k => !(k.indexOf('limits.') == 0 && requested['requests.' + k.substring(7)]));
      var parts = keys.map(k => (names[k] || k) + ': needs ' + requested[k] + ', but ' + (used[k] || '?') + ' of the ' + (limited[k] || '?') + ' allowed is already in use');
      result.text = 'Not enough resources in ' + namespace + ' to start ' + subject + '. Its quota \'' + m[1] + '\' is full (' + parts.join('; ') + '). ' + fix;
    } else {
      result.text = 'Not enough resources in ' + namespace + ' to start ' + subject + ' (Kubernetes: ' + latest.substring(latest.indexOf('exceeded quota')).trim().substring(0, 300) + '). ' + fix;
    }
    return result;
  }

  var full = (input.quotaRows || []).filter(r => r.utilizationPercentage >= 90)
    .map(r => r.resourceType + ' ' + r.currentValue + ' of ' + r.maxValue + ' ' + r.format + ' in use (' + r.utilizationPercentage + '%)');
  if (full.length) return { refused: false, text: capitalise(namespace) + ' is almost out of quota (' + full.join(', ') + '), which is the likely reason ' + subject + ' did not start. ' + fix };

  // a pod waiting for a node is normal while the node pool scales up, so only a recent one counts
  var unscheduled = evidence.filter(x => x.event && x.text.indexOf('Insufficient') >= 0 && now - x.ms <= 3 * 60 * 1000).pop();
  if (unscheduled) return { refused: false, text: 'No node in the cluster has room for ' + subject + ' (' + unscheduled.text.trim().replace(/\.$/, '').substring(0, 300) + '). The cluster needs more or larger nodes, or other workloads on it need to stop.' };

  return null;
}
