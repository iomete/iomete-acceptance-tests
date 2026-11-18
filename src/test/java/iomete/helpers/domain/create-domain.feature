@ignore
Feature: Create a domain.
  Split out of ensure-domain.feature so the create is one step with one status to assert.
  Call it with:
    karate.call('classpath:iomete/helpers/domain/create-domain.feature',
                { domainId: 'karate' })
  or, for a domain owned by one user, private when isPrivate is true (which needs the
  privateDomains rollout flag, see enable-private-domains.feature):
    karate.call('classpath:iomete/helpers/domain/create-domain.feature',
                { domainId: 'karate-priv-...', owner: 'karate-priv-owner-...', isPrivate: true })

  Scenario: create the domain
    * def owner = karate.get('owner', null)
    * def isPrivate = karate.get('isPrivate', false) == true
    # an owner is only set through the v2 create, which answers 201 instead of 200
    * def createPath = owner ? 'api/v2/admin/domains' : 'api/v1/admin/domains'
    * def createdStatus = owner ? 201 : 200
    * def body = owner ? { id: domainId, name: domainId, owner: { id: owner, type: 'USER' }, isPrivate: isPrivate } : { id: domainId, name: domainId }

    # a flag just turned on takes a moment to reach iom-identity, which refuses the private create meanwhile
    * configure retry = { count: 12, interval: 10000 }
    Given url baseUrl
    And path createPath
    And request body
    And retry until !(isPrivate && responseStatus == 400 && karate.toString(response).contains('feature is not enabled'))
    When method post
    # a deleted domain keeps its id reserved, which is what a repeat under a cleaned-up run id meets
    * if (responseStatus != createdStatus) karate.fail('could not create domain ' + domainId + ' (' + responseStatus + '): ' + karate.toString(response) + '. If an earlier cleanup deleted it, run `make clean` or set a new IOMETE_RUN_ID')
    * if (isPrivate && response.isPrivate != true) karate.fail('domain ' + domainId + ' was created but is not private: ' + karate.toString(response))
