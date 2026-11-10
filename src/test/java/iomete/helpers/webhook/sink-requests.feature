@ignore
Feature: List the webhook requests the test sink received on one channel (helper).
  Usage:
    karate.call('classpath:iomete/helpers/webhook/sink-requests.feature', { channel: '...' }).events
    karate.call('classpath:iomete/helpers/webhook/sink-requests.feature', { channel: '...', sinkWaitFor: 'FAILED' }).events
  Returns: events, oldest first, each { body, json }: the body as received and parsed. With sinkWaitFor (an
  eventType) it asks again every 5s, for up to 5 minutes, until an event of that type is there,
  and fails the step if none arrives.

  The sink is not part of IOMETE, so the suite's IOMETE headers are not sent to it.

  Scenario: list
    * def login = karate.callSingle('classpath:iomete/helpers/webhook/sink-login.feature')
    * configure headers = { Authorization: '#(login.basic)' }
    # the input has a name no caller uses: karate.get also sees the caller's variables
    * def wanted = karate.get('sinkWaitFor', null)
    * def eventsIn = function(r) { return ((r && r.requests) || []).map(x => ({ body: x.body, json: JSON.parse(x.body) })) }
    # the platform retries a failed delivery after 30s and 2m, so this outlasts the first three attempts
    * configure retry = { count: 60, interval: 5000 }
    Given url login.sinkUrl
    And path 'api/hooks', channel
    And retry until responseStatus != 200 || !wanted || eventsIn(response).some(e => e.json.eventType == wanted)
    When method get
    Then status 200
    * def events = eventsIn(response)
