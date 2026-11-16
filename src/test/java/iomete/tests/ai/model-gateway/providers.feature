@lock=api
Feature: Model Gateway provider list, the catalog of providers the gateway supports

  `/llm-gateway/v1/admin/providers` lists every provider this release of the gateway supports,
  with the auth types a connection to it may use and the dialects it routes. It is read-only and
  comes from the gateway's own catalog, so it writes nothing and needs no teardown. What only the
  real platform can show is that the route answers an admin through the gateway, in that shape,
  and that `gcp` routes both the `openai` dialect (Gemini) and the `anthropic` one (Claude). The
  whole list, its ordering and the admin gate are covered by iom-ai-services' tests.

  The whole feature skips on platforms older than 4.1.0, which predate the list (builds from main
  count as newer), and where the AI services are not enabled: `ai-services/version` answers 404
  then. Where they are enabled, the gateway route has to work, so a 404 on it fails.

  Background:
    * if (!platformAtLeast('4.1.0')) karate.log('platform ' + platformVersion + ' predates the Model Gateway provider list, skipping')
    * if (!platformAtLeast('4.1.0')) karate.abort()

    * url baseUrl

    # the AI services are optional
    * if (!aiServicesEnabled()) karate.log('AI services are not enabled on this target, skipping')
    * if (!aiServicesEnabled()) karate.abort()

    * def providersPath = 'llm-gateway/v1/admin/providers'

  Scenario: an admin lists the providers, each with its auth types and dialects, and gcp routes both dialects
    Given path providersPath
    When method get
    Then status 200
    And match response.items == '#[_ > 0]'
    And match each response.items == { provider: '#string', auth_types: '#[_ > 0] #string', dialects: '#[_ > 0] #string' }

    * def gcp = response.items.filter(p => p.provider == 'gcp')
    And match gcp == '#[1]'
    And match gcp[0].dialects contains only [ 'anthropic', 'openai' ]
    And match gcp[0].auth_types contains 'gcp_service_account'
