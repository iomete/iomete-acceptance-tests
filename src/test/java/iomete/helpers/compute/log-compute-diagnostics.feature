@ignore
Feature: Log what the platform reports about a compute that did not become ready.
  Called by create-compute.feature before it gives up, while the compute still exists:
    karate.call('classpath:iomete/helpers/compute/log-compute-diagnostics.feature',
                { computeId: '...', computeName: 'my-compute', why: 'driver never became ACTIVE' })
  Reads the compute's status, pods, Kubernetes events, recent driver and executor logs and its
  namespace's quota, and logs a short summary of each. It never fails: a call that errors is
  logged with its status, so the caller's own failure is what the run reports.

  Scenario: log the compute's status, pods, events, recent logs and namespace quota
    * def computePath = 'api/v2/domains/' + domain + '/compute'
    * def logTailLines = 40
    # karate.log skips the logging mask, so everything printed here goes through redact()
    * def section = function(title, text) { karate.log('[diagnostics ' + computeName + '] ' + title + ':\n' + redact(text)) }
    * def short = function(body) { var text = typeof body == 'string' ? body : JSON.stringify(body); return text.length > 2000 ? text.substring(0, 2000) + '...' : text }
    * def logLines = function(entries) { return entries.slice(-logTailLines).map(e => e.logLine).join('\n') }
    * karate.log('[diagnostics ' + computeName + '] ' + redact(why))

    # status, without the endpoints and Spark conf, which can carry connection details
    Given url baseUrl
    And path computePath, computeId
    When method get
    * def compute = responseStatus == 200 ? response : null
    * def summary = compute ? { driverStatus: compute.driverStatus, driverErrorMessage: compute.driverErrorMessage, executorsState: compute.executorsState, restartCount: compute.restartCount, isRestartRequired: compute.isRestartRequired, namespace: compute.namespace, dataPlane: compute.dataPlane, image: compute.image, nodeTypes: compute.nodeTypes, updatedAt: compute.updatedAt } : null
    * section('status (' + responseStatus + ')', short(summary ? summary : response))

    Given url baseUrl
    And path computePath, computeId, 'activity'
    When method get
    * section('recent actions (' + responseStatus + ')', short(response))

    # driver and executor pods with their phase
    Given url baseUrl
    And path computePath, computeId, 'instances'
    When method get
    * def instances = responseStatus == 200 && Array.isArray(response) ? response : []
    * section('instances (' + responseStatus + ')', short(response))

    # driver pod and SparkApplication events: scheduling, image pulls, mounts, executor failures
    Given url baseUrl
    And path computePath, computeId, 'events'
    When method get
    # newest last, and only the last 30: a crash-looping compute can have hundreds
    * def eventTime = function(e) { return String(e.lastObservedTime || e.eventTime || '') }
    * def events = responseStatus == 200 && Array.isArray(response) ? response.sort((a, b) => eventTime(a) < eventTime(b) ? -1 : eventTime(a) > eventTime(b) ? 1 : 0).slice(-30) : []
    * def eventLines = events.map(e => eventTime(e) + ' ' + e.type + ' ' + e.reason + ' ' + e.regardingObjectKind + '/' + e.regardingObjectName + (e.eventCount > 1 ? ' (x' + e.eventCount + ')' : '') + ': ' + e.note).join('\n')
    * section('events (' + responseStatus + ')', events.length ? eventLines : short(response))

    # the driver log carries executor requests refused by the quota and Thrift start errors
    Given url baseUrl
    And path computePath, computeId, 'logs'
    And param range = '15m'
    When method get
    * section('driver log, last ' + logTailLines + ' lines (' + responseStatus + ')', responseStatus == 200 && Array.isArray(response) ? logLines(response) : short(response))

    * def executors = instances.filter(p => !p.name.endsWith('-driver'))
    * def logExecutor =
      """
      function(pod) {
        var res = karate.call('classpath:iomete/helpers/compute/read-instance-logs.feature', { computeId: computeId, instanceName: pod.name });
        section('executor ' + pod.name + ' log, last ' + logTailLines + ' lines (' + res.status + ')', res.status == 200 && Array.isArray(res.body) ? logLines(res.body) : short(res.body));
      }
      """
    * karate.forEach(executors, logExecutor)

    # quota used vs hard in the compute's namespace (v3 reads the copy the agent pushes)
    Given url baseUrl
    And path 'api/v3/domains', domain, 'namespaces', 'quotas'
    When method get
    * def namespaceRows = responseStatus == 200 && Array.isArray(response) && compute ? response.filter(n => n.namespace == compute.namespace) : null
    * section('namespace quota (' + responseStatus + ')', short(namespaceRows ? namespaceRows : response))
