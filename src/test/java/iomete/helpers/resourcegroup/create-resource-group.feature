@ignore
Feature: Create a resource group (plumbing).
  Call it with:
    karate.call('classpath:iomete/helpers/resourcegroup/create-resource-group.feature',
                { name: 'karate-rg-' + runId })
  Optional: description, owner ({ id, type: 'USER'|'GROUP' }), tags ({ key: value }).
  Not get-or-create — names carry runId, so a collision means a leftover from a failed run;
  callers should delete that first rather than silently reuse it.
  Returns:
    groupId  the created resource group's UUID
    group    the full ResourceGroupResponse

  Scenario: create the resource group
    * def description = karate.get('description', 'karate api tests')
    * def owner = karate.get('owner', null)
    * def tags = karate.get('tags', null)
    * def createRequest =
      """
      {
        name: '#(name)',
        description: '#(description)',
        domainId: '#(domain)',
        owner: ##(owner),
        tags: ##(tags)
      }
      """

    Given url baseUrl
    And path 'api/v1/resource-groups'
    And request createRequest
    When method post
    Then status 200
    * def group = response
    * def groupId = group.groupId
    * match groupId == '#notnull'
