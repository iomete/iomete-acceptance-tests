@lock=api
Feature: Model Gateway chat route, its refusals and the request id

  `POST llm-gateway/v1/chat/completions` is the gateway's data plane: the route callers' SDKs use.
  The feature never gets a successful answer from a provider, because the suite's `openai`
  connection holds a fake key, so it covers the refusals only the real gateway, registry and
  platform can prove together: what a provider's refusal of the stored key becomes, who is let in,
  what a missing, disabled or unknown model answers, and the request id every response carries.
  Successful chat, streaming, usage fields and the request body's type validation stay in
  iom-ai-services' tests, as does the use-permission refusal.

  One scenario needs nothing from the platform's state (no token, an unmatched path), so it runs
  everywhere the gateway does. The other two create a connection over a fake key and list the fixed
  `karate-model` provider model, which has no delete endpoint and stays in the registry, so they run
  only where `IOMETE_ALLOW_PLATFORM_CHANGES` allows that, like `connections.feature`.

  The key-refusal scenario needs the provider to answer. An install with no way out (an air-gapped
  customer) gets the gateway's own no-answer replies instead, and a busy provider answers 429, 500
  or 503; the scenario skips on both, as `connection-test.feature` excuses them.

  The gateway caches a registry row for 30 seconds and remembers a missing or disabled name for 5,
  so a scenario never flips a flag on a name it has already called. The disabled cases are created
  disabled instead, each under a name of its own, and called once.

  The whole feature skips on platforms older than 4.0.2, which predate the Model Gateway (builds
  from main count as newer), and where the AI services are not enabled. Where they are enabled,
  the gateway route has to work, so a 404 on it fails.

  Background:
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the Model Gateway, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()

    * url baseUrl

    * if (!aiServicesEnabled()) karate.log('AI services are not enabled on this target, skipping')
    * if (!aiServicesEnabled()) karate.abort()

    * def chatPath = 'llm-gateway/v1/chat/completions'
    * def connectionsPath = 'llm-gateway/v1/admin/connections'
    * def providerModelsPath = 'llm-gateway/v1/admin/provider-models'
    * def keysPath = 'llm-gateway/v1/admin/provider-keys'
    # connection and key names must be lowercase, which runId already is. The endpoint name the
    # gateway derives is `{connection}-{model}`, capped at 63 characters, so these stay short
    * def connName = 'karate-chat-conn-' + runId
    * def offModelConnName = 'karate-chat-moff-' + runId
    * def offConnName = 'karate-chat-coff-' + runId
    * def keyName = 'karate-chat-key-' + runId
    # fake: the provider has to refuse it, and nothing here ever reaches a real account
    * def keyValue = 'karate-chat-key-value-' + runId
    # fixed: provider models cannot be deleted
    * def providerModel = 'karate-model'
    # a request id a client might send; the gateway makes its own and never echoes this one
    * def clientId = 'karate-client-request-id-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }
    * def chatBody = function(model) { return { model: model, messages: [{ role: 'user', content: 'ping' }] }; }
    # the values of a response header by name, whatever the case the server spelled it in; [] when absent
    * def responseHeaderValues = function(name) { var wanted = name.toLowerCase(); var all = karate.get('responseHeaders'); for (var k in all) { if (k.toLowerCase() == wanted) return all[k]; } return []; }
    # the first value, or null when the header is absent
    * def responseHeader = function(name) { var values = responseHeaderValues(name); return values.length > 0 ? values[0] : null; }
    # every header the response carries, lowercased
    * def headerNames = function() { var names = []; var all = karate.get('responseHeaders'); for (var k in all) names.push(k.toLowerCase()); return names; }

    # teardown: back to admin first, since a scenario may have cleared the headers. Each step is a
    # no-op when its object is gone; any other failure fails the teardown
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var failures = [];
        var steps = [
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: connName }, what: 'connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: offModelConnName }, what: 'connection with a disabled model' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: offConnName }, what: 'disabled connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: keyName }, what: 'provider key' }
        ];
        steps.forEach(function(step) {
          try {
            karate.call(step.feature, step.args);
          } catch (e) {
            karate.log(step.what + ' teardown failed:', e);
            failures.push(step.what + ': ' + e);
          }
        });
        if (failures.length > 0) throw 'teardown failed: ' + failures.join('; ');
      }
      """

    # the AI services are enabled, so the gateway routes have to answer
    Given path connectionsPath
    When method get
    Then status 200

  Scenario: a provider's refusal of the stored key is a 502 that tells SDKs not to retry and relays nothing of the provider's
    # creates a provider model that stays, so only where the install allows that
    * if (!platformChangesAllowed()) karate.log('IOMETE_ALLOW_PLATFORM_CHANGES is not true, skipping a test that lists a provider model')
    * if (!platformChangesAllowed()) karate.abort()

    # delete first: `make test-one` reuses the run id, so a killed attempt leaves its objects behind
    * def clearedConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(connName)' }
    * def clearedKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(keyName)' }

    # the credential and the provider model the connection points at: 201, or 409 for the model when
    # an earlier run already listed it (there is no delete)
    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    Given path providerModelsPath
    And request { provider: 'openai', model: '#(providerModel)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path connectionsPath
    And request { name: '#(connName)', provider: 'openai', auth_type: 'static_bearer', secret_ref: '#(keyName)', models: [{ name: '#(connName)', model: '#(providerModel)' }] }
    When method post
    Then status 201
    # the gateway may qualify a model's name with its connection's, so the chat uses the name it returned
    * def endpoint = response.models[0].name

    # the key is fake, so OpenAI answers 401. The gateway answers for the provider: a 502 of its own,
    # never the provider's 401 (which a client reads as a refusal of its own token)
    Given path chatPath
    And header x-iomete-request-id = clientId
    And request chatBody(endpoint)
    When method post

    # an install with no way out to the provider gets the gateway's no-answer replies, and a busy
    # provider answers 429/500/503: both say nothing about the refusal this scenario is about
    * def noReply = providerBusy(responseStatus) || (response.error && gatewayNoAnswer(responseStatus, response.error.message))
    * if (noReply) karate.log('the provider gave no verdict on the key (' + responseStatus + '), skipping the refusal check')
    * if (noReply) karate.abort()

    Then status 502
    And match response.error.code == 'upstream_error'
    And match response.error.type == 'iomete_gateway_error'
    # the gateway's own refusal of an unusable stored key is also a 502 upstream_error, so what
    # shows the provider refused is this message and the provider's own error object under upstream
    And match response.error.message == "backend refused the connection's credential"
    And match response.error.upstream == '#notnull'
    And match responseHeader('x-should-retry') == 'false'
    And match responseHeader('x-iomete-request-id') == '#string'
    And assert responseHeader('x-iomete-request-id') != clientId

    # nothing of the provider's own answer is relayed with the refusal. OpenAI's 401 may not send
    # any of these today, so this is a guard against a relay and not proof that one was dropped. Only
    # names OpenAI alone sends are checked: an edge in front of the install adds its own (cf-ray)
    And assert responseHeader('www-authenticate') == null
    And assert headerNames().filter(n => n.startsWith('openai-') || n.startsWith('x-openai-')).length == 0
    # and the stored key's value is not echoed
    And assert !karate.pretty(response).contains(keyValue)

  Scenario: no token is a 401 and an unmatched path answers the JSON envelope, each with a request id of the gateway's own
    * configure headers = {}

    Given path chatPath
    And header x-iomete-request-id = clientId
    And request chatBody('karate-no-such-model-' + runId)
    When method post
    Then status 401
    And match response.error.code == 'invalid_token'
    And match response.error.type == 'iomete_gateway_error'
    And match responseHeader('x-iomete-request-id') == '#string'
    And assert responseHeader('x-iomete-request-id') != clientId
    * def unauthorizedId = responseHeader('x-iomete-request-id')

    * configure headers = adminHeaders

    # not net/http's plain-text 404: the catch-all renders the gateway's own envelope. It sits outside
    # the plane middleware and makes its id itself, so it is checked on its own
    Given path 'llm-gateway/v1/karate-no-such-route-' + runId
    And header x-iomete-request-id = clientId
    When method get
    Then status 404
    And match responseHeader('content-type') contains 'application/json'
    And match response.error.type == 'iomete_gateway_error'
    And match response.error.code == 'invalid_request'
    And match responseHeader('x-iomete-request-id') == '#string'
    And assert responseHeader('x-iomete-request-id') != clientId
    # a fresh id for every response
    And assert responseHeader('x-iomete-request-id') != unauthorizedId

  Scenario: an unknown, a disabled and a model under a disabled connection all answer the same 404
    # creates a provider model that stays, so only where the install allows that
    * if (!platformChangesAllowed()) karate.log('IOMETE_ALLOW_PLATFORM_CHANGES is not true, skipping a test that lists a provider model')
    * if (!platformChangesAllowed()) karate.abort()

    * def clearedOffModel = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(offModelConnName)' }
    * def clearedOffConn = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(offConnName)' }
    * def clearedKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(keyName)' }

    # the credential and the provider model the connection points at: 201, or 409 for the model when
    # an earlier run already listed it (there is no delete)
    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    Given path providerModelsPath
    And request { provider: 'openai', model: '#(providerModel)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    # a model that is off, under a connection that is on
    Given path connectionsPath
    And request { name: '#(offModelConnName)', provider: 'openai', auth_type: 'static_bearer', secret_ref: '#(keyName)', models: [{ name: '#(offModelConnName)', model: '#(providerModel)', enabled: false }] }
    When method post
    Then status 201
    And match response.models[0].enabled == false
    * def offModel = response.models[0].name

    # a model that is on, under a connection that is off
    Given path connectionsPath
    And request { name: '#(offConnName)', provider: 'openai', auth_type: 'static_bearer', secret_ref: '#(keyName)', enabled: false, models: [{ name: '#(offConnName)', model: '#(providerModel)' }] }
    When method post
    Then status 201
    And match response.enabled == false
    * def offConnModel = response.models[0].name

    # missing, disabled model and disabled connection are deliberately indistinguishable: a caller
    # learns nothing about what is registered. The messages match too, apart from the model's own name
    * def unknownName = 'karate-no-such-model-' + runId

    Given path chatPath
    And header x-iomete-request-id = clientId
    And request chatBody(unknownName)
    When method post
    Then status 404
    And match response.error.code == 'unknown_endpoint'
    And match response.error.type == 'iomete_gateway_error'
    And match responseHeader('x-iomete-request-id') == '#string'
    And assert responseHeader('x-iomete-request-id') != clientId
    * def unknownCode = response.error.code
    * def unknownMessage = response.error.message.replace(unknownName, '<model>')

    Given path chatPath
    And header x-iomete-request-id = clientId
    And request chatBody(offModel)
    When method post
    Then status 404
    And match response.error.code == unknownCode
    And match response.error.type == 'iomete_gateway_error'
    And match responseHeader('x-iomete-request-id') == '#string'
    And assert responseHeader('x-iomete-request-id') != clientId
    And match response.error.message.replace(offModel, '<model>') == unknownMessage

    Given path chatPath
    And header x-iomete-request-id = clientId
    And request chatBody(offConnModel)
    When method post
    Then status 404
    And match response.error.code == unknownCode
    And match response.error.type == 'iomete_gateway_error'
    And match responseHeader('x-iomete-request-id') == '#string'
    And assert responseHeader('x-iomete-request-id') != clientId
    And match response.error.message.replace(offConnModel, '<model>') == unknownMessage
