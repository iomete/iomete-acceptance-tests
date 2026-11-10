@lock=api
Feature: Vault configs — IOMETE connects to a real Vault and lists its secrets

  What this checks:
  - The connection test reaches the real Vault: the right token is accepted, a wrong one is not.
  - A saved Vault config makes the secret stored in Vault show up in the domain's secret list.
  - Deleting the config removes those secrets from the list again.

  Needs a test Vault the platform can reach, holding one secret, and a read-only token for it.
  Skips unless IOMETE_VAULT_ADDRESS, IOMETE_VAULT_TOKEN, IOMETE_VAULT_SECRET_PATH and
  IOMETE_VAULT_SECRET_KEY are set (see AGENTS.md).

  Not tested here (covered by iom-cluster's own tests): saving, editing and validating configs,
  and IOMETE's own authorization (who may save, edit or delete a config). Saving a config never contacts Vault, so those need no real Vault.
  Not tested yet: the secret's value reaching a compute. That needs the secretsV2 flag, a
  compute or job that takes the secret into its Spark config, and a job that compares the value
  inside Spark (SQL SET shows it redacted).

  Background:
    * url baseUrl
    * def env = function(name, fallback){ return java.lang.System.getenv(name) || fallback }
    * def vaultAddr = env('IOMETE_VAULT_ADDRESS', null)
    * def vaultToken = env('IOMETE_VAULT_TOKEN', null)
    # The full Vault API path of the test secret (KV v2), and the key stored in it.
    * def vaultPath = env('IOMETE_VAULT_SECRET_PATH', null)
    * def vaultKey = env('IOMETE_VAULT_SECRET_KEY', null)
    * def settings = ({ IOMETE_VAULT_ADDRESS: vaultAddr, IOMETE_VAULT_TOKEN: vaultToken, IOMETE_VAULT_SECRET_PATH: vaultPath, IOMETE_VAULT_SECRET_KEY: vaultKey })
    * def missing = Object.keys(settings).filter(k => !settings[k])
    * def configured = missing.length == 0
    # name what is missing, so a half-published setup is visible instead of a silent skip
    * if (!configured) karate.log('no test Vault configured, missing:', missing.join(', '), '- skipping')
    * if (!configured) karate.abort()
    * def configName = 'karate-vault-' + runId
    * def configsPath = 'api/v1/domains/' + domain + '/vault-configs'
    * def secretsPath = 'api/v2/domains/' + domain + '/secrets'
    # The connection test takes the same body as saving a config, so it needs a name and bundle too.
    Given path 'api/v1/bundles'
    And params { scope: 'OWNED', domain: '#(domain)' }
    When method get
    Then status 200
    * def bundle = response.items[0]
    And match bundle == '#notnull'
    * def bundleId = bundle.bundleId
    * def connection = function(token) { return { name: configName, bundleId: bundleId, host: vaultAddr, path: vaultPath, authMethod: 'TOKEN', authCredentials: { token: token } } }

    # Remove any config left by an earlier attempt, and remove ours when the test ends.
    * def removeConfig = function() { karate.call('classpath:iomete/helpers/secret/delete-vault-config.feature', { name: configName }) }
    * removeConfig()
    * configure afterScenario = function() { removeConfig() }

  Scenario: the connection test accepts the right token and rejects a wrong one
    # Step 1: the right token reads the test secret.
    Given path configsPath, 'test-connection'
    And request connection(vaultToken)
    When method post
    Then status 200

    # Step 2: a wrong token is rejected by Vault (Vault answers 403), and IOMETE reports it.
    Given path configsPath, 'test-connection'
    And request connection('karate-not-a-real-token')
    When method post
    Then status 400
    And match response.errorMessage == 'Vault credential verification failed: Permission denied to the specified path'

  Scenario: a saved config lists the Vault secret, and deleting it removes the secret from the list
    # Step 1: save a Vault config in the domain's bundle.
    Given path configsPath
    And request connection(vaultToken)
    When method post
    Then status 201
    * def configId = response.id

    # Step 2: the secret list reads Vault and shows the test secret, marked as coming from it.
    Given path secretsPath
    When method get
    Then status 200
    And match response contains deep { key: '#(vaultKey)', source: { type: 'VAULT', id: '#(configId)', name: '#(configName)' } }

    # Step 3: delete the config. It leaves the config list, and its secrets leave the secret list.
    Given path configsPath, configId
    When method delete
    Then status 204

    Given path configsPath
    When method get
    Then status 200
    And match response[*].item.id !contains configId

    Given path secretsPath
    When method get
    Then status 200
    And match response[*].source.id !contains configId
