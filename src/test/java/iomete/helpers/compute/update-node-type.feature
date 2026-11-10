@ignore
Feature: Update one node type in place (plumbing), called per drifted entry of ensure-node-types.feature.

  Scenario: update it
    Given url baseUrl
    And path 'api/v1/admin/node-types', 'name', name
    And request { name: '#(name)', description: '#(description)', memory: '#(memory)', cpu: '#(cpu)', spot: '#(spot)', components: '#(components)' }
    When method put
    # 403: this token cannot manage node types — the run proceeds on the sizes already registered
    Then assert responseStatus == 200 || responseStatus == 204 || responseStatus == 403
