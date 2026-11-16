@lock=api
Feature: Model Gateway connection test, probing a connection its body describes without saving it

  `POST llm-gateway/v1/admin/connections/test` takes a create body without a name, sends each
  enabled model one minimal completion through the data plane and answers 200 with a result per
  model, in request order. It stores nothing. The console builds its Test button on it, so the
  main flow is what this feature checks over the real platform: the secret reference resolves
  against the platform's secret store, the model is checked against the provider's list, and the
  probe goes out through the real forwarder.

  A successful probe needs a real provider key, so the suite probes with a fake one and checks
  that the provider's own verdict comes back: `success: false`, a `latency_ms`, and an
  `error.status` and `error.message`. A refused key is the provider's 401 or 403, not the data
  plane's 502 rewrite. Whether the data plane can reach the provider at all depends on the
  install (an air-gapped one cannot), so every result is held to 401/403 except a busy provider
  (429, 500, 503, or Anthropic's 529) and the gateway's own no-answer 502/504. The shape is checked everywhere.

  Provider models have no delete endpoint, so the two this feature lists (`karate-model` and
  `karate-test-model`, both openai) have fixed names and stay in the registry, like the ones in
  `connections.feature`; the whole feature therefore runs only where
  `IOMETE_ALLOW_PLATFORM_CHANGES` allows that. Shape and grammar refusals, and the admin gate,
  stay in iom-ai-services' tests.

  The whole feature skips on platforms older than 4.0.2, which predate the Model Gateway (builds
  from main count as newer), and where the AI services are not enabled: `ai-services/version`
  answers 404 then. Where they are enabled, the gateway route has to work, so a 404 on it fails.

  Background:
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the Model Gateway, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()
    # leaves provider models behind, since there is no delete, so it runs only where the install allows that
    * if (!platformChangesAllowed()) karate.abort()

    * url baseUrl

    # the AI services are optional
    * if (!aiServicesEnabled()) karate.log('AI services are not enabled on this target, skipping')
    * if (!aiServicesEnabled()) karate.abort()

    * def connectionsPath = 'llm-gateway/v1/admin/connections'
    * def testPath = 'llm-gateway/v1/admin/connections/test'
    * def providerModelsPath = 'llm-gateway/v1/admin/provider-models'
    * def endpointsPath = 'llm-gateway/v1/admin/endpoints'
    * def keysPath = 'llm-gateway/v1/admin/provider-keys'
    # fixed: provider models cannot be deleted, so a per-run name would add a row to the list every run.
    # `karate-model` sorts before `karate-test-model`, so listing them the other way round shows the
    # results follow the request and not the alphabet
    * def modelA = 'karate-test-model'
    * def modelB = 'karate-model'
    # connection and key names must be lowercase, which runId already is
    * def keyName = 'karate-ctest-key-' + runId
    * def keyValue = 'karate-ctest-key-value-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # teardown: the key only, since the test saves no connection. A no-op when it is gone; any
    # other failure fails the teardown
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        try {
          karate.call('classpath:iomete/helpers/ai/delete-provider-key.feature', { key: keyName });
        } catch (e) {
          karate.log('provider key teardown failed:', e);
          throw 'teardown failed: provider key: ' + e;
        }
      }
      """

    # the AI services are enabled, so the gateway routes have to answer
    Given path connectionsPath
    When method get
    Then status 200

    # delete first: `make test-one` reuses the run id, so a killed attempt leaves its key behind
    * def clearedKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(keyName)' }

    # the provider models every probe below names: 201, or 409 once any run listed them
    Given path providerModelsPath
    And request { provider: 'openai', model: '#(modelA)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409
    Given path providerModelsPath
    And request { provider: 'openai', model: '#(modelB)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

  Scenario: a connection over a fake key is probed per enabled model in request order, and nothing is stored
    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    # two models in request order (a model can only appear once in a body)
    Given path testPath
    And request
      """
      {
        provider: 'openai', auth_type: 'static_bearer', secret_ref: '#(keyName)',
        models: [
          { model: '#(modelA)' },
          { model: '#(modelB)' }
        ]
      }
      """
    When method post
    Then status 200
    And match response.results == '#[2]'
    And match response.results[*].model == [ '#(modelA)', '#(modelB)' ]
    # the key is fake, so no probe can succeed, and each failure carries the provider's own verdict
    And match each response.results == { model: '#string', success: false, latency_ms: '#number', error: { status: '#number', message: '#string' } }

    * karate.log('connection test results:', response.results)
    # a refused key is the provider's own 401 or 403. The data plane's rewrite of it is a 502 whose
    # message can be the provider's text, so it cannot be told apart by message; instead only the
    # gateway's own "no answer" outcomes are excused (a data plane with no way out), and every
    # other result, a 502 with a provider message included, is held to 401/403
    * def excused = function(r) { return providerBusy(r.error.status) || gatewayNoAnswer(r.error.status, r.error.message) }
    * def refused = function(r) { return r.error.status == 401 || r.error.status == 403 }
    * def answered = karate.filter(response.results, function(r) { return !excused(r) })
    * match karate.filter(answered, refused) == answered

    # the body has no name and the test saves nothing: no connection and no endpoint is left
    # pointing at the key. Looked up by the run's own key, since other runs add and remove their
    # own connections on this target while this one runs
    # secret_ref is a plain name in some listings and a resolved object with a `key` in others
    * def usesKey = function(x) { var r = x.secret_ref; return (r && typeof r == 'object') ? r.key == keyName : r == keyName }
    Given path connectionsPath
    When method get
    Then status 200
    And match karate.filter(response.items, usesKey) == []

    Given path endpointsPath
    When method get
    Then status 200
    And match karate.filter(response.items, usesKey) == []
