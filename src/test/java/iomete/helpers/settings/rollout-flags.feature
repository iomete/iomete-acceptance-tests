@ignore
Feature: Read the platform's rollout flags, the way the console and MCP read them.
  Rollout flags (sqlEditorV2 among them) are set by an admin at runtime and are not in the
  flag map feature-flags.feature reads, which comes from the install's configuration. Only a
  flag with a platform-wide value is listed, so a missing flag is off. An admin can change one
  mid-run, so call it where the value is used rather than once per run:
    karate.call('classpath:iomete/helpers/settings/rollout-flags.feature', { baseUrl: baseUrl })
  Returns:
    flags  the flag map, keyed by flag name, true or false

  Scenario: fetch the rollout flag values
    Given url baseUrl
    And path 'api/v1/feature-flags/values'
    When method get
    Then status 200
    * def flags = response
