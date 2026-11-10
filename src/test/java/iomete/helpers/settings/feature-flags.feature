@ignore
Feature: Read the environment's feature flags.
  The platform gates whole behaviours behind flags, so a scenario that only holds with one
  of them on has to ask before it runs. Call it once per run with:
    karate.callSingle('classpath:iomete/helpers/settings/feature-flags.feature',
                      { baseUrl: baseUrl })
  Returns:
    flags  the flag map, keyed by the platform's own flag names

  Scenario: fetch the flag map
    Given url baseUrl
    And path 'api/v1/modules'
    When method get
    Then status 200
    * def flags = response
