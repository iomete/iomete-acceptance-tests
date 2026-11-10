@ignore
Feature: Log what the platform reports about an event stream that did not start.
  Called before a wait on the stream gives up, while the stream still exists:
    karate.call('classpath:iomete/helpers/event-stream/log-stream-diagnostics.feature',
                { streamId: '...', streamName: 'my-stream', namespace: '...', why: 'never became ACTIVE' })
  Logs the stream's status, pods, Kubernetes events and its namespace's quota. It never fails:
  a call that errors is logged with its status, so the caller's own failure is what the run reports.

  Scenario: log the stream's status, pods, events and namespace quota
    * def streamPath = 'api/v1/domains/' + domain + '/event-streams'
    # karate.log skips the logging mask, so everything printed here goes through redact()
    * def section = function(title, text) { karate.log('[diagnostics ' + streamName + '] ' + title + ':\n' + redact(text)) }
    * def short = function(body) { var text = typeof body == 'string' ? body : JSON.stringify(body); return text.length > 2000 ? text.substring(0, 2000) + '...' : text }
    * karate.log('[diagnostics ' + streamName + '] ' + redact(why))

    # status only, without the stream's config, which can carry connection details
    Given url baseUrl
    And path streamPath, streamId
    When method get
    * def stream = responseStatus == 200 ? response : null
    * def summary = stream ? { status: stream.status, ready: stream.ready, replicas: stream.replicas, namespace: stream.namespace } : null
    * section('status (' + responseStatus + ')', short(summary ? summary : response))

    Given url baseUrl
    And path streamPath, streamId, 'pods'
    When method get
    * def pods = responseStatus == 200 && Array.isArray(response) ? response : null
    * section('pods (' + responseStatus + ')', pods ? pods.map(p => p.name + ' ' + p.status).join('\n') : short(response))

    # scheduling, image pulls and crash loops show up here, newest last
    Given url baseUrl
    And path streamPath, streamId, 'events'
    When method get
    * def eventTime = function(e) { return String(e.lastObservedTime || e.eventTime || '') }
    * def events = responseStatus == 200 && Array.isArray(response) ? response.sort((a, b) => eventTime(a) < eventTime(b) ? -1 : eventTime(a) > eventTime(b) ? 1 : 0).slice(-30) : []
    * def eventLines = events.map(e => eventTime(e) + ' ' + e.type + ' ' + e.reason + ' ' + e.regardingObjectKind + '/' + e.regardingObjectName + (e.eventCount > 1 ? ' (x' + e.eventCount + ')' : '') + ': ' + e.note).join('\n')
    * section('events (' + responseStatus + ')', events.length ? eventLines : short(response))

    # quota used vs hard in the stream's namespace
    Given url baseUrl
    And path 'api/v3/domains', domain, 'namespaces', 'quotas'
    When method get
    * def namespaceRows = responseStatus == 200 && Array.isArray(response) ? response.filter(n => n.namespace == namespace) : null
    * section('namespace quota (' + responseStatus + ')', short(namespaceRows ? namespaceRows : response))
