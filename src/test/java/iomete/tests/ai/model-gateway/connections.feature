@lock=api
Feature: Model Gateway connections and provider models, the admin API over the gateway's registry

  A connection ties a provider to a provider key (the credential, stored in the platform's secret
  store) and carries the models callers address. A provider model is an id the gateway lists as
  attachable to that provider's connections; a connection's model has to be one of them. What only
  the real platform can prove is that a connection created over a real provider key resolves that
  secret, and lists and reads back with its models and never the key's value. The admin gate,
  syntax rules, the validation order and the registry's own uniqueness handling are covered by
  iom-ai-services' tests and stay out of here, except the two azure refusals below, which are
  worth seeing on the real platform.

  A `gcp` connection can also address one self-deployed Vertex endpoint: its provider config then
  carries an `endpoint_id` and the endpoint's `dedicated_host`. Registering one never contacts
  Google. The gateway only parses the stored secret as a service-account key file, so the scenario
  generates a throwaway RSA key into a fake file at run time and needs no GCP credentials. It
  checks the config round trip: stored as sent, and resolved for the model. The endpoint
  grammar's refusals stay in iom-ai-services' tests.

  A provider model names the dialect it speaks. `gcp` routes two, so from 4.1.0 a Google connection
  serves a Claude model in the `anthropic` dialect beside a Gemini one in `openai`, a model listed
  under `gcp` without a dialect is refused, and the resolved view carries each model's dialect.
  Platforms from before the field (up to 4.0.2-rc4) refuse it as unknown, so the other steps send
  it only where the platform knows it. A chat through the connection needs a real Google key and
  is not covered.

  Azure serves Claude from the same resource as its OpenAI deployments, so from 4.1.0 an `azure`
  connection holds a Claude deployment in the `anthropic` dialect beside an OpenAI one, and the
  resolved view carries each one's dialect. A chat through it needs a real Azure resource and is
  not covered.

  An `azure` connection also carries a provider config, the `resource`: the subdomain of the Azure
  endpoint URL, which becomes the host the gateway calls. Its models are deployment names. Nothing
  contacts Azure at registration, so the resource and the deployment need not exist; the scenario
  checks that the config is stored and resolved, and that the catalog's two refusals hold on the
  real platform (a resource outside the subdomain grammar, an auth type Azure does not take).

  An `anthropic` connection takes no provider config, and its models speak the `anthropic` dialect,
  which the provider implies. Nothing contacts Anthropic at registration; the scenario checks that
  the empty config is stored and resolved. The catalog's refusals stay in iom-ai-services' tests.

  Provider models have no delete endpoint, so the models this feature lists (`karate-model` for
  openai, `karate-vertex-model` and `karate-vertex-claude` for gcp, `karate-deployment` and
  `karate-azure-claude` for azure, `karate-claude-model` for anthropic) have fixed names and stay
  in the registry like the domain does: no run deletes them, so overlapping runs cannot take them from each other, and the list
  keeps one row per provider and model pair however many runs there are.

  The whole feature skips on platforms older than 4.0.2, which predate the Model Gateway (builds
  from main count as newer), and where the AI services are not enabled: `ai-services/version`
  answers 404 then. Where they are enabled, the gateway route has to work, so a 404 on it fails.

  Background:
    * if (!platformAtLeast('4.0.2')) karate.log('platform ' + platformVersion + ' predates the Model Gateway, skipping')
    * if (!platformAtLeast('4.0.2')) karate.abort()
    # leaves a provider model behind, since there is no delete, so it runs only where the install allows that
    * if (!platformChangesAllowed()) karate.abort()

    * url baseUrl

    # the AI services are optional
    * if (!aiServicesEnabled()) karate.log('AI services are not enabled on this target, skipping')
    * if (!aiServicesEnabled()) karate.abort()

    * def connectionsPath = 'llm-gateway/v1/admin/connections'
    * def providerModelsPath = 'llm-gateway/v1/admin/provider-models'
    * def keysPath = 'llm-gateway/v1/admin/provider-keys'
    # connection and model names must be lowercase, which runId already is
    * def connName = 'karate-conn-' + runId
    * def modelName = 'karate-conn-model-' + runId
    # fixed: provider models cannot be deleted, so a per-run name would add a row to the list every run
    * def providerModel = 'karate-model'
    * def keyName = 'karate-conn-key-' + runId
    * def keyValue = 'karate-conn-key-value-' + runId
    * def gcpConnName = 'karate-gcp-conn-' + runId
    * def gcpKeyName = 'karate-gcp-key-' + runId
    # fixed, like providerModel: a model id the gcp provider's list keeps
    * def gcpProviderModel = 'karate-vertex-model'
    # synthetic: it names no real Google project. A run id can be a 32-character UUID
    # (IOMETE_RUN_ID) and Google caps a project id at 30 characters, so only this one is cut
    * def gcpProject = 'karate-vx-' + runId.substring(0, 20)
    * def gcpEndpointId = 'karate-ep-' + runId
    * def gcpLocation = 'us-central1'
    * def gcpDedicatedHost = gcpEndpointId + '.' + gcpLocation + '-1234567890.prediction.vertexai.goog'
    * def azureConnName = 'karate-azure-conn-' + runId
    # fixed, like providerModel: a deployment name the azure provider's list keeps
    * def azureDeployment = 'karate-deployment'
    # the subdomain grammar: lowercase letters, digits and hyphens, which runId already is
    * def azureResource = 'karate-res-' + runId
    # Claude on an Azure connection, next to the OpenAI deployment. Fixed, like azureDeployment
    * def azureClaudeDeployment = 'karate-azure-claude'
    * def azureClaudeConnName = 'karate-azure-claude-conn-' + runId
    * def anthropicConnName = 'karate-anthropic-conn-' + runId
    # fixed, like providerModel: a model id the anthropic provider's list keeps
    * def anthropicProviderModel = 'karate-claude-model'
    * def endpointsPath = 'llm-gateway/v1/admin/endpoints'
    # a provider model names its dialect from 4.0.2-rc5 on. A provider that routes more than one
    # dialect needs it, while an older gateway refuses the unknown field with a 400
    * def dialectKnown = platformAtLeast('4.0.2-rc5')
    * def withDialect = function(body, dialect) { return dialectKnown ? karate.merge(body, { dialect: dialect }) : body }
    # Claude on a Google connection, next to a Gemini model. Fixed, like gcpProviderModel
    * def gcpClaudeModel = 'karate-vertex-claude'
    * def gcpClaudeConnName = 'karate-gcp-claude-conn-' + runId
    * def gcpClaudeKeyName = 'karate-gcp-claude-key-' + runId
    * def singleConnName = 'karate-single-conn-' + runId
    * def singleKeyName = 'karate-single-key-' + runId
    * def effectiveConnName = 'karate-effective-conn-' + runId
    * def effectiveKeyName = 'karate-effective-key-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # a gcp credential: a service-account key file for a throwaway RSA key, made at run time, since
    # registration only parses it (no GCP credentials, no committed key)
    * def generateKeyFile =
      """
      function(projectId) {
        var generator = Java.type('java.security.KeyPairGenerator').getInstance('RSA');
        generator.initialize(2048);
        var der = generator.generateKeyPair().getPrivate().getEncoded();
        var body = Java.type('java.util.Base64').getEncoder().encodeToString(der).replace(/(.{64})/g, '$1\n');
        return JSON.stringify({
          type: 'service_account',
          project_id: projectId,
          private_key_id: 'karate0000000000000000000000000000000000',
          private_key: '-----BEGIN PRIVATE KEY-----\n' + body.replace(/\n$/, '') + '\n-----END PRIVATE KEY-----\n',
          client_email: 'karate@' + projectId + '.iam.gserviceaccount.com',
          token_uri: 'https://oauth2.googleapis.com/token'
        });
      }
      """

    # teardown: back to admin first, since the failure that triggers this may have left the
    # scenario acting as another user. The connection goes before its key, models first.
    # Each step is a no-op when its object is gone; any other failure fails the teardown
    * def baseTeardown =
      """
      function() {
        karate.configure('headers', adminHeaders);
        var failures = [];
        var steps = [
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: connName }, what: 'connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: gcpConnName }, what: 'gcp connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: azureConnName }, what: 'azure connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: azureClaudeConnName }, what: 'azure claude connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: anthropicConnName }, what: 'anthropic connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: singleConnName }, what: 'single-model connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: effectiveConnName }, what: 'effective-flag connection' },
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: keyName }, what: 'provider key' },
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: gcpKeyName }, what: 'gcp provider key' },
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: singleKeyName }, what: 'single-model provider key' },
          { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: effectiveKeyName }, what: 'effective-flag provider key' }
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
    * configure afterScenario = baseTeardown

    # the AI services are enabled, so the gateway routes have to answer
    Given path connectionsPath
    When method get
    Then status 200
    Given path providerModelsPath
    When method get
    Then status 200

    # delete first: `make test-one` reuses the run id, so a killed attempt leaves its objects behind
    * def clearedConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(connName)' }
    * def clearedGcpConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(gcpConnName)' }
    * def clearedAzureConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(azureConnName)' }
    * def clearedAzureClaudeConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(azureClaudeConnName)' }
    * def clearedKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(keyName)' }
    * def clearedGcpKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(gcpKeyName)' }
    * def clearedAnthropicConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(anthropicConnName)' }
    * def clearedSingleConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(singleConnName)' }
    * def clearedEffectiveConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(effectiveConnName)' }
    * def clearedSingleKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(singleKeyName)' }
    * def clearedEffectiveKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(effectiveKeyName)' }

  Scenario: a provider model is listed, then a connection over a real provider key is created with it, read, replaced, refused deletion while it has models, and removed
    # the credential the connection points at: a real key in the platform's secret store
    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    # the connection's model has to be in the provider's list: 201, or 409 when an earlier attempt
    # of this run already listed it (there is no delete)
    Given path providerModelsPath
    And request { provider: 'openai', model: '#(providerModel)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And param provider = 'openai'
    When method get
    Then status 200
    And match response.items[*].model contains providerModel

    # create: 201, with the pinned secret reference and the embedded model
    Given path connectionsPath
    And request { name: '#(connName)', provider: 'openai', auth_type: 'static_bearer', secret_ref: '#(keyName)', models: [{ name: '#(modelName)', model: '#(providerModel)' }] }
    When method post
    Then status 201
    And match response.name == connName
    And match response.provider == 'openai'
    And match response.auth_type == 'static_bearer'
    And match response.enabled == true
    And match response.secret_ref.key == keyName
    And match response.secret_ref.source.type == 'KUBERNETES'
    And match response.models == '#[1]'
    And match response.models[0] contains { connection: '#(connName)', model: '#(providerModel)', enabled: true }
    # the gateway may qualify a model's name with its connection's, so later calls use the name it returned
    * def createdModelName = response.models[0].name
    And assert !karate.pretty(response).contains(keyValue)

    # listed with a count in place of the rows, and no secret value
    Given path connectionsPath
    When method get
    Then status 200
    * def listed = response.items.filter(c => c.name == connName)
    And match listed == '#[1]'
    And match listed[0].models_count == 1
    And match listed[0] contains { provider: 'openai', enabled: true }
    And assert !karate.pretty(response).contains(keyValue)

    # the detail carries the models
    Given path connectionsPath, connName
    When method get
    Then status 200
    And match response.models[*].name contains createdModelName
    And match response.secret_ref.key == keyName
    And assert !karate.pretty(response).contains(keyValue)

    # replace: a full object; the body of a GET is a valid PUT body
    * def detail = response
    * set detail.enabled = false
    Given path connectionsPath, connName
    And request detail
    When method put
    Then status 200
    And match response.enabled == false
    And match response.models == '#[1]'

    # a connection that still has models cannot be deleted, and the refusal removes nothing
    Given path connectionsPath, connName
    When method delete
    Then status 409
    And match response.error.code == 'connection_in_use'

    Given path connectionsPath, connName
    When method get
    Then status 200
    And match response.models[*].name == [ '#(createdModelName)' ]

    # delete: models first, then the connection
    Given path connectionsPath, connName, 'models', createdModelName
    When method delete
    Then status 204

    Given path connectionsPath, connName
    When method delete
    Then status 204

    Given path connectionsPath
    When method get
    Then status 200
    And match response.items[*].name !contains connName

  Scenario: a gcp connection stores its self-deployed endpoint and resolves it for its model
    # the credential: a service-account key file (generateKeyFile, in the Background)
    * def keyFile = generateKeyFile(gcpProject)
    Given path keysPath
    And request { key: '#(gcpKeyName)', value: '#(keyFile)' }
    When method post
    Then status 201

    # the model has to be in the gcp provider's list: 201, or 409 once any run listed it
    Given path providerModelsPath
    And request withDialect({ provider: 'gcp', model: gcpProviderModel }, 'openai')
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And param provider = 'gcp'
    When method get
    Then status 200
    And match response.items[*].model contains gcpProviderModel

    * def gcpConfig = { project_id: '#(gcpProject)', location: '#(gcpLocation)', endpoint_id: '#(gcpEndpointId)', dedicated_host: '#(gcpDedicatedHost)' }
    * def gcpConnection =
      """
      {
        name: '#(gcpConnName)', provider: 'gcp', auth_type: 'gcp_service_account', secret_ref: '#(gcpKeyName)',
        config: '#(gcpConfig)',
        models: [{ model: '#(gcpProviderModel)' }]
      }
      """

    # create: the config comes back exactly as sent
    Given path connectionsPath
    And request gcpConnection
    When method post
    Then status 201
    And match response contains { name: '#(gcpConnName)', provider: 'gcp', auth_type: 'gcp_service_account', enabled: true }
    And match response.config == gcpConfig
    And match response.secret_ref.key == gcpKeyName
    And match response.models == '#[1]'
    And match response.models[0] contains { connection: '#(gcpConnName)', model: '#(gcpProviderModel)', enabled: true }
    * def gcpModelName = response.models[0].name
    And assert !karate.pretty(response).contains('PRIVATE KEY')

    # the resolved view, what the data plane serves a caller's model from, carries the config
    Given path endpointsPath, gcpModelName
    When method get
    Then status 200
    And match response contains { connection: '#(gcpConnName)', provider: 'gcp', model: '#(gcpProviderModel)', enabled: true }
    And match response.config == gcpConfig
    And assert !karate.pretty(response).contains('PRIVATE KEY')

    # delete: models first, then the connection
    Given path connectionsPath, gcpConnName, 'models', gcpModelName
    When method delete
    Then status 204

    Given path connectionsPath, gcpConnName
    When method delete
    Then status 204

    Given path connectionsPath, gcpConnName
    When method get
    Then status 404

  Scenario: a gcp connection serves a Claude model beside a Gemini one, each in its own dialect, and a gcp model without a dialect is refused
    # gcp routes Claude through the Anthropic dialect from 4.1.0 (builds from main count as newer)
    * if (!platformAtLeast('4.1.0')) karate.log('platform ' + platformVersion + ' predates Claude on gcp connections, skipping')
    * if (!platformAtLeast('4.1.0')) karate.abort()

    # this scenario's own cleanup, so the other scenarios do not pay for it. The shared teardown
    # runs first, then the connection before its key (a no-op when the object is gone)
    * def claudeCleanup =
      """
      [
        { feature: 'classpath:iomete/helpers/ai/delete-connection.feature', args: { name: gcpClaudeConnName }, what: 'gcp claude connection' },
        { feature: 'classpath:iomete/helpers/ai/delete-provider-key.feature', args: { key: gcpClaudeKeyName }, what: 'gcp claude provider key' }
      ]
      """
    * configure afterScenario =
      """
      function() {
        var failures = [];
        try { baseTeardown(); } catch (e) { failures.push(String(e)); }
        karate.configure('headers', adminHeaders);
        claudeCleanup.forEach(function(step) {
          try {
            karate.call(step.feature, step.args);
          } catch (e) {
            karate.log(step.what + ' teardown failed:', e);
            failures.push(step.what + ': ' + e);
          }
        });
        if (failures.length > 0) throw failures.join('; ');
      }
      """
    # delete first: `make test-one` reuses the run id, so a killed attempt leaves its objects behind
    * def clearedGcpClaudeConnection = call read('classpath:iomete/helpers/ai/delete-connection.feature') { name: '#(gcpClaudeConnName)' }
    * def clearedGcpClaudeKey = call read('classpath:iomete/helpers/ai/delete-provider-key.feature') { key: '#(gcpClaudeKeyName)' }

    # gcp routes two dialects, so a model listed without one is refused, a listed id included
    Given path providerModelsPath
    And request { provider: 'gcp', model: '#(gcpProviderModel)' }
    When method post
    Then status 400
    And match response.error.code == 'invalid_configuration'
    # the message pins which check refused it, since any other 400 shares the code; the dialect list stays out of it
    And match response.error.message contains 'dialect is required'

    # the Gemini model and the Claude one, each in its dialect: 201, or 409 once any run listed it
    Given path providerModelsPath
    And request { provider: 'gcp', model: '#(gcpProviderModel)', dialect: 'openai' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And request { provider: 'gcp', model: '#(gcpClaudeModel)', dialect: 'anthropic' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And param provider = 'gcp'
    When method get
    Then status 200
    * def listedClaude = response.items.filter(m => m.model == gcpClaudeModel)
    And match listedClaude == '#[1]'
    And match listedClaude[0].dialect == 'anthropic'
    * def listedGemini = response.items.filter(m => m.model == gcpProviderModel)
    And match listedGemini == '#[1]'
    And match listedGemini[0].dialect == 'openai'

    # the credential: a service-account key file (generateKeyFile, in the Background)
    * def keyFile = generateKeyFile(gcpProject)
    Given path keysPath
    And request { key: '#(gcpClaudeKeyName)', value: '#(keyFile)' }
    When method post
    Then status 201

    # no endpoint_id: Claude is a publisher model, which a self-deployed endpoint does not serve
    * def gcpCatalogConfig = { project_id: '#(gcpProject)', location: '#(gcpLocation)' }
    Given path connectionsPath
    And request { name: '#(gcpClaudeConnName)', provider: 'gcp', auth_type: 'gcp_service_account', secret_ref: '#(gcpClaudeKeyName)', config: '#(gcpCatalogConfig)', models: [{ model: '#(gcpProviderModel)' }, { model: '#(gcpClaudeModel)' }] }
    When method post
    Then status 201
    And match response contains { name: '#(gcpClaudeConnName)', provider: 'gcp', enabled: true }
    And match response.config == gcpCatalogConfig
    And match response.models == '#[2]'
    And match response.models[*].model contains only [ '#(gcpProviderModel)', '#(gcpClaudeModel)' ]
    And assert !karate.pretty(response).contains('PRIVATE KEY')
    * def geminiName = response.models.filter(m => m.model == gcpProviderModel)[0].name
    * def claudeName = response.models.filter(m => m.model == gcpClaudeModel)[0].name

    # the resolved view: each model speaks the dialect it was listed in
    Given path endpointsPath, geminiName
    When method get
    Then status 200
    And match response contains { connection: '#(gcpClaudeConnName)', provider: 'gcp', model: '#(gcpProviderModel)', dialect: 'openai', enabled: true }
    And assert !karate.pretty(response).contains('PRIVATE KEY')

    Given path endpointsPath, claudeName
    When method get
    Then status 200
    And match response contains { connection: '#(gcpClaudeConnName)', provider: 'gcp', model: '#(gcpClaudeModel)', dialect: 'anthropic', enabled: true }
    And match response.config == gcpCatalogConfig
    And assert !karate.pretty(response).contains('PRIVATE KEY')

    # delete: models first, then the connection
    Given path connectionsPath, gcpClaudeConnName, 'models', geminiName
    When method delete
    Then status 204

    Given path connectionsPath, gcpClaudeConnName, 'models', claudeName
    When method delete
    Then status 204

    Given path connectionsPath, gcpClaudeConnName
    When method delete
    Then status 204

    Given path connectionsPath, gcpClaudeConnName
    When method get
    Then status 404

  Scenario: an azure connection stores its resource and resolves it for its deployment, and the catalog refuses a bad resource and a foreign auth type
    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    # the deployment has to be in the azure provider's list: 201, or 409 once any run listed it
    Given path providerModelsPath
    And request withDialect({ provider: 'azure', model: azureDeployment }, 'openai')
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And param provider = 'azure'
    When method get
    Then status 200
    And match response.items[*].model contains azureDeployment

    * def azureConnection =
      """
      {
        name: '#(azureConnName)', provider: 'azure', auth_type: 'static_bearer', secret_ref: '#(keyName)',
        config: { resource: '#(azureResource)' },
        models: [{ model: '#(azureDeployment)' }]
      }
      """

    # a resource outside the subdomain grammar is refused: it would become the host
    * def badResource = karate.merge(azureConnection, { config: { resource: 'Karate.Res' } })
    Given path connectionsPath
    And request badResource
    When method post
    Then status 400
    And match response.error.code == 'invalid_configuration'
    # the message pins which check refused it, since any other 400 shares the code
    And match response.error.message contains 'resource must be the subdomain'

    # Azure takes a key only: a service-account auth type is refused by the catalog
    * def badAuth = karate.merge(azureConnection, { auth_type: 'gcp_service_account' })
    Given path connectionsPath
    And request badAuth
    When method post
    Then status 400
    And match response.error.code == 'invalid_configuration'
    And match response.error.message contains 'is not supported for provider'

    # neither refusal stored anything
    Given path connectionsPath, azureConnName
    When method get
    Then status 404

    # create: the resource comes back as the connection's config
    Given path connectionsPath
    And request azureConnection
    When method post
    Then status 201
    And match response contains { name: '#(azureConnName)', provider: 'azure', auth_type: 'static_bearer', enabled: true }
    And match response.config == { resource: '#(azureResource)' }
    And match response.secret_ref.key == keyName
    And match response.models == '#[1]'
    And match response.models[0] contains { connection: '#(azureConnName)', model: '#(azureDeployment)', enabled: true }
    * def azureModelName = response.models[0].name
    And assert !karate.pretty(response).contains(keyValue)

    # the resolved view, what the data plane serves a caller's model from, carries the resource
    Given path endpointsPath, azureModelName
    When method get
    Then status 200
    And match response contains { connection: '#(azureConnName)', provider: 'azure', model: '#(azureDeployment)', enabled: true }
    And match response.config == { resource: '#(azureResource)' }
    And assert !karate.pretty(response).contains(keyValue)

    # delete: models first, then the connection
    Given path connectionsPath, azureConnName, 'models', azureModelName
    When method delete
    Then status 204

    Given path connectionsPath, azureConnName
    When method delete
    Then status 204

    Given path connectionsPath, azureConnName
    When method get
    Then status 404

  Scenario: an anthropic connection stores an empty config and resolves it for its Claude model
    # the anthropic provider came after the first gateway release
    * if (!platformAtLeast('4.1.0')) karate.log('platform ' + platformVersion + ' predates the anthropic provider, skipping')
    * if (!platformAtLeast('4.1.0')) karate.abort()

    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    # no dialect: the provider routes one, so it is implied. 201, or 409 once any run listed it
    Given path providerModelsPath
    And request { provider: 'anthropic', model: '#(anthropicProviderModel)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And param provider = 'anthropic'
    When method get
    Then status 200
    * def listed = response.items.filter(m => m.model == anthropicProviderModel)
    And match listed == '#[1]'
    And match listed[0].dialect == 'anthropic'

    # create: Anthropic takes no provider config, so it comes back empty
    Given path connectionsPath
    And request { name: '#(anthropicConnName)', provider: 'anthropic', auth_type: 'static_bearer', secret_ref: '#(keyName)', config: {}, models: [{ model: '#(anthropicProviderModel)' }] }
    When method post
    Then status 201
    And match response contains { name: '#(anthropicConnName)', provider: 'anthropic', auth_type: 'static_bearer', enabled: true }
    And match response.config == {}
    And match response.secret_ref.key == keyName
    And match response.models == '#[1]'
    And match response.models[0] contains { connection: '#(anthropicConnName)', model: '#(anthropicProviderModel)', enabled: true }
    * def anthropicModelName = response.models[0].name
    And assert !karate.pretty(response).contains(keyValue)

    # the resolved view, what the data plane serves a caller's model from, carries the empty config
    Given path endpointsPath, anthropicModelName
    When method get
    Then status 200
    And match response contains { connection: '#(anthropicConnName)', provider: 'anthropic', model: '#(anthropicProviderModel)', enabled: true }
    And match response.config == {}
    And assert !karate.pretty(response).contains(keyValue)

    # delete: models first, then the connection
    Given path connectionsPath, anthropicConnName, 'models', anthropicModelName
    When method delete
    Then status 204

    Given path connectionsPath, anthropicConnName
    When method delete
    Then status 204

    Given path connectionsPath, anthropicConnName
    When method get
    Then status 404

  Scenario: an azure connection serves a Claude deployment beside an OpenAI one, each in its own dialect
    # Claude on azure goes through the Anthropic dialect from 4.1.0 (builds from main count as newer)
    * if (!platformAtLeast('4.1.0')) karate.log('platform ' + platformVersion + ' predates Claude on azure connections, skipping')
    * if (!platformAtLeast('4.1.0')) karate.abort()

    Given path keysPath
    And request { key: '#(keyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    # the OpenAI deployment and the Claude one, each in its dialect: 201, or 409 once any run listed it
    Given path providerModelsPath
    And request { provider: 'azure', model: '#(azureDeployment)', dialect: 'openai' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And request { provider: 'azure', model: '#(azureClaudeDeployment)', dialect: 'anthropic' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path providerModelsPath
    And param provider = 'azure'
    When method get
    Then status 200
    * def listedClaude = response.items.filter(m => m.model == azureClaudeDeployment)
    And match listedClaude == '#[1]'
    And match listedClaude[0].dialect == 'anthropic'
    * def listedOpenai = response.items.filter(m => m.model == azureDeployment)
    And match listedOpenai == '#[1]'
    And match listedOpenai[0].dialect == 'openai'

    # one connection, one resource and key, both deployments
    Given path connectionsPath
    And request { name: '#(azureClaudeConnName)', provider: 'azure', auth_type: 'static_bearer', secret_ref: '#(keyName)', config: { resource: '#(azureResource)' }, models: [{ model: '#(azureDeployment)' }, { model: '#(azureClaudeDeployment)' }] }
    When method post
    Then status 201
    And match response contains { name: '#(azureClaudeConnName)', provider: 'azure', enabled: true }
    And match response.config == { resource: '#(azureResource)' }
    And match response.models == '#[2]'
    And match response.models[*].model contains only [ '#(azureDeployment)', '#(azureClaudeDeployment)' ]
    And assert !karate.pretty(response).contains(keyValue)
    * def openaiName = response.models.filter(m => m.model == azureDeployment)[0].name
    * def claudeName = response.models.filter(m => m.model == azureClaudeDeployment)[0].name

    # the resolved view: each deployment speaks the dialect it was listed in, on the same resource
    Given path endpointsPath, openaiName
    When method get
    Then status 200
    And match response contains { connection: '#(azureClaudeConnName)', provider: 'azure', model: '#(azureDeployment)', dialect: 'openai', enabled: true }
    And match response.config == { resource: '#(azureResource)' }
    And match response.secret_ref.key == keyName
    And assert !karate.pretty(response).contains(keyValue)

    Given path endpointsPath, claudeName
    When method get
    Then status 200
    And match response contains { connection: '#(azureClaudeConnName)', provider: 'azure', model: '#(azureClaudeDeployment)', dialect: 'anthropic', enabled: true }
    And match response.config == { resource: '#(azureResource)' }
    And match response.secret_ref.key == keyName
    And assert !karate.pretty(response).contains(keyValue)

    # delete: models first, then the connection
    Given path connectionsPath, azureClaudeConnName, 'models', openaiName
    When method delete
    Then status 204

    Given path connectionsPath, azureClaudeConnName, 'models', claudeName
    When method delete
    Then status 204

    Given path connectionsPath, azureClaudeConnName
    When method delete
    Then status 204

    Given path connectionsPath, azureClaudeConnName
    When method get
    Then status 404

  Scenario: a single model is added to a connection, switched off and read back
    Given path keysPath
    And request { key: '#(singleKeyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    # a connection with nothing beneath it is legal; its models arrive through the model routes
    Given path connectionsPath
    And request { name: '#(singleConnName)', provider: 'openai', auth_type: 'static_bearer', secret_ref: '#(singleKeyName)' }
    When method post
    Then status 201
    And match response.models == '#[0]'

    # the model has to be in the provider's list (the same fixed id as above: 201, or 409 once listed)
    Given path providerModelsPath
    And request { provider: 'openai', model: '#(providerModel)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    # create: 201 with the one model. The gateway derives the name, so later calls use the one it returned
    Given path connectionsPath, singleConnName, 'models'
    And request { model: '#(providerModel)' }
    When method post
    Then status 201
    And match response contains { connection: '#(singleConnName)', model: '#(providerModel)', enabled: true }
    * def singleModel = response

    # PUT is a full replace of the model row: the body of the create is a valid PUT body with `enabled` flipped
    * set singleModel.enabled = false
    Given path connectionsPath, singleConnName, 'models', singleModel.name
    And request singleModel
    When method put
    Then status 200
    And match response contains { name: '#(singleModel.name)', connection: '#(singleConnName)', model: '#(providerModel)', enabled: false }

    # read back: exactly one model, now off
    Given path connectionsPath, singleConnName
    When method get
    Then status 200
    And match response.models == '#[1]'
    And match response.models[0] contains { name: '#(singleModel.name)', enabled: false }

  Scenario: the endpoints view reports a model enabled only while its connection and the model both are
    Given path keysPath
    And request { key: '#(effectiveKeyName)', value: '#(keyValue)' }
    When method post
    Then status 201

    Given path providerModelsPath
    And request { provider: 'openai', model: '#(providerModel)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    Given path connectionsPath
    And request { name: '#(effectiveConnName)', provider: 'openai', auth_type: 'static_bearer', secret_ref: '#(effectiveKeyName)', models: [{ model: '#(providerModel)' }] }
    When method post
    Then status 201
    * def effectiveModel = response.models[0].name

    # both on: the endpoint is on
    Given path endpointsPath, effectiveModel
    When method get
    Then status 200
    And match response.enabled == true

    # the connection off: the endpoint is off, while the model resource still says on
    Given path connectionsPath, effectiveConnName
    When method get
    Then status 200
    # no models in the PUT body: the service keeps them as they are, so only the connection's own
    # flag changes and the model's raw flag below is a real check, not a resent value
    * def effectiveConn = response
    * remove effectiveConn.models
    * set effectiveConn.enabled = false
    Given path connectionsPath, effectiveConnName
    And request effectiveConn
    When method put
    Then status 200
    And match response.enabled == false

    Given path endpointsPath, effectiveModel
    When method get
    Then status 200
    And match response.enabled == false

    Given path connectionsPath, effectiveConnName
    When method get
    Then status 200
    And match response.enabled == false
    And match response.models[0] contains { name: '#(effectiveModel)', enabled: true }

    # the connection back on and the model off: the endpoint is still off, the connection reads on
    * set effectiveConn.enabled = true
    Given path connectionsPath, effectiveConnName
    And request effectiveConn
    When method put
    Then status 200
    And match response.enabled == true

    Given path connectionsPath, effectiveConnName, 'models', effectiveModel
    And request { name: '#(effectiveModel)', model: '#(providerModel)', enabled: false }
    When method put
    Then status 200
    And match response.enabled == false

    Given path endpointsPath, effectiveModel
    When method get
    Then status 200
    And match response.enabled == false

    Given path connectionsPath, effectiveConnName
    When method get
    Then status 200
    And match response.enabled == true
    And match response.models[0] contains { name: '#(effectiveModel)', enabled: false }

    # both on again: the endpoint is back on
    Given path connectionsPath, effectiveConnName, 'models', effectiveModel
    And request { name: '#(effectiveModel)', model: '#(providerModel)', enabled: true }
    When method put
    Then status 200

    Given path endpointsPath, effectiveModel
    When method get
    Then status 200
    And match response.enabled == true
