@ignore
Feature: Create a domain.
  Split out of ensure-domain.feature so the create is one step with one status to assert.
  Call it with:
    karate.call('classpath:iomete/helpers/domain/create-domain.feature',
                { domainId: 'karate' })

  Scenario: create the domain
    Given url baseUrl
    And path 'api/v1/admin/domains'
    And request { id: '#(domainId)', name: '#(domainId)' }
    When method post
    # a deleted domain keeps its id reserved, which is what a repeat under a cleaned-up run id meets
    * if (responseStatus != 200) karate.fail('could not create domain ' + domainId + ' (' + responseStatus + '): ' + karate.toString(response) + '. If an earlier cleanup deleted it, run `make clean` or set a new IOMETE_RUN_ID')
