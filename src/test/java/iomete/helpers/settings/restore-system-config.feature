@ignore
Feature: Put one system setting back the way a scenario found it.
  Call with:
    karate.call('classpath:iomete/helpers/settings/restore-system-config.feature', { name: 'x', before: { value: 60, overridden: false } })
  An override that was there before is written back, otherwise the override is reset to the default.

  Scenario: restore the setting
    Given url baseUrl
    * if (!before.overridden) karate.abort()
    And path 'api/v1/admin/system-config'
    And request { name: '#(name)', value: '#(before.value)' }
    When method put
    Then status 200

  Scenario: reset the setting
    Given url baseUrl
    * if (before.overridden) karate.abort()
    And path 'api/v1/admin/system-config', name
    When method delete
    Then status 200
