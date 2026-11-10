@ignore
Feature: Register one node type (plumbing), called per entry of ensure-node-types.feature.

  Scenario: register it
    Given url baseUrl
    And path 'api/v1/admin/node-types'
    And request { name: '#(name)', description: '#(description)', memory: '#(memory)', cpu: '#(cpu)', spot: '#(spot)', components: '#(components)' }
    When method post
    # 409: a concurrent run got there first. 403: this token cannot manage node types, so the
    # picker falls back to the smallest stock type.
    Then assert responseStatus == 200 || responseStatus == 201 || responseStatus == 409 || responseStatus == 403
