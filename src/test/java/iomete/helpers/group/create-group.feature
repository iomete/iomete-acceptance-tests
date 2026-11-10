@ignore
Feature: Create (or reuse) a group so other tests have somewhere to put members and roles.
  Callers pass a name; description is optional and defaults deterministically so re-runs
  reuse the same group:
    karate.call('classpath:iomete/helpers/group/create-group.feature',
                { name: 'karate-test-group' })
  Returns:
    name   the group name
    group  the full group record from GET .../groups/{name}

  Scenario: create the group if missing (409 = already there), then load its record
    * def description = karate.get('description', 'karate api tests')
    * def groupsPath = 'api/v1/admin/identity/groups'

    # create if missing — 409 means the name is taken, which is fine
    Given url baseUrl
    And path groupsPath
    And request { name: '#(name)', description: '#(description)' }
    When method post
    Then assert responseStatus == 201 || responseStatus == 409

    # load the record so callers get a consistent shape whether we created or reused it
    Given url baseUrl
    And path groupsPath, name
    When method get
    Then status 200
    * def group = response.item
    * match group == '#notnull'
