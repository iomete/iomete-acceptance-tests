@lock=api
Feature: System settings, an admin override is applied and then put back

  One main flow through the admin system settings: override one setting, read it back from the
  admin list and the user endpoint, then put it back the way it was. Settings are platform-wide, so the
  scenario uses one whose override is harmless (see AGENTS.md, System settings).

  Background:
    # changes platform-wide state, so it runs only where the install allows that
    * if (!platformChangesAllowed()) karate.abort()
    * url baseUrl
    * def adminPath = 'api/v1/admin/system-config'
    * def userPath = 'api/v1/system-config'
    * def settingName = 'spark-application.retention-days'
    # 0 turns off deleting old job runs, so the override only ever keeps more history
    * def overrideValue = 0
    # an override comes back as a string, a default as a number
    * def asText = function(v) { return '' + v }
    * def restorePath = 'classpath:iomete/helpers/settings/restore-system-config.feature'

    # put the setting back if a step failed after the override was written
    * def changed = false
    * def restored = false
    * configure afterScenario =
      """
      function() {
        if (changed && !restored) karate.call(restorePath, { name: settingName, before: before });
      }
      """

  Scenario: an override shows in the admin list and the user endpoint, and putting it back restores the earlier value
    # 4.0.0 has the key but defaults it to 0, so there is nothing to override there
    * if (!platformAtLeast('4.0.1')) karate.abort()
    # Step 1: read the setting as it stands, which is what the restore puts back
    Given path adminPath
    When method get
    Then status 200
    * def current = response.find(s => s.name == settingName)
    * match current contains { name: '#(settingName)', value: '#notnull', defaultValue: '#notnull', description: '#string' }
    # an override equal to the default reads the same as none, and resetting it changes nothing
    # already 0 (an admin's choice, or an override a killed run left): nothing to prove, so skip, but fail in CI
    * def inCi = java.lang.System.getenv('GITHUB_ACTIONS') == 'true'
    * if (asText(current.value) == asText(overrideValue)) { var reason = settingName + ' is already ' + overrideValue + ', reset it if a killed run left it'; if (inCi) karate.fail(reason); karate.log(reason + ', skipping'); karate.abort() }
    * def before = { value: '#(current.value)', overridden: '#(asText(current.value) != asText(current.defaultValue))' }

    # Step 2: override it, marked first so a lost response still gets restored
    * def changed = true
    Given path adminPath
    And request { name: '#(settingName)', value: '#(overrideValue)' }
    When method put
    Then status 200

    # Step 3: both views read the override back
    Given path adminPath
    When method get
    Then status 200
    * match asText(response.find(s => s.name == settingName).value) == asText(overrideValue)

    Given path userPath
    When method get
    Then status 200
    * match asText(response.find(s => s.name == settingName).value) == asText(overrideValue)

    # Step 4: put it back and read the earlier value again
    * karate.call(restorePath, { name: settingName, before: before })
    * def restored = true

    Given path adminPath
    When method get
    Then status 200
    * match asText(response.find(s => s.name == settingName).value) == asText(before.value)
