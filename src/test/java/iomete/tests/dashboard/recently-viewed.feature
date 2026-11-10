@lock=api
Feature: Recently viewed items stay isolated per domain

  Business-rule and access-control variants live in TestContainers-backed unit tests in the
  monorepo. This suite keeps just the one happy path a live run can prove: per-domain isolation.

  Background:
    * url baseUrl
    * def recentPath = 'api/v1/domains/' + domain + '/dashboard/recently-viewed'

  Scenario: the same user sees isolated lists across the two domains it belongs to
    # a second domain of the scenario's own where domains can be deleted, named per attempt since
    # a deleted id stays reserved; older platforms share a fixed one
    * def domainB = domainOwnedByRun ? 'karate-rv-' + runId + '-' + java.lang.Long.toString(java.lang.System.currentTimeMillis(), 36) : 'karate-secondary'
    * def recentPathB = 'api/v1/domains/' + domainB + '/dashboard/recently-viewed'
    * def multiDomainUser = 'karate-recent-multi-domain-user-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # runs pass or fail, as admin: the scenario switches to the user's token below
    * configure afterScenario =
      """
      function() {
        karate.configure('headers', adminHeaders);
        try { karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: multiDomainUser }); } catch (e) { karate.log('user teardown failed:', e); }
        if (domainOwnedByRun) karate.call('classpath:iomete/helpers/domain/delete-domain.feature', { domain: domainB });
      }
      """

    # membership in both domains
    * karate.call('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domainB })
    * def cleared = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(multiDomainUser)' }
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(multiDomainUser)' }
    * def grantedA = call read('classpath:iomete/helpers/domain/grant-domain-permissions.feature') { username: '#(multiDomainUser)', permissions: [] }
    * def grantedB = call read('classpath:iomete/helpers/domain/grant-domain-permissions.feature') { username: '#(multiDomainUser)', domain: '#(domainB)', permissions: [] }
    * def login = call read('classpath:iomete/helpers/user/login.feature') { username: '#(multiDomainUser)', password: '#(created.temporaryPassword)' }
    * configure headers = { Authorization: '#("Bearer " + login.accessToken)' }

    * def registerDomainA = { assetType: 'karate-table', assetId: 'karate-recent-domain-a-item', displayName: 'Karate Recent Domain A Item' }
    * def registerDomainB = { assetType: 'karate-table', assetId: 'karate-recent-domain-b-item', displayName: 'Karate Recent Domain B Item' }

    # register one item per domain
    Given path recentPath
    And request registerDomainA
    When method post
    Then status 204

    Given path recentPathB
    And request registerDomainB
    When method post
    Then status 204

    # list domain A — only its own item, not domain B's
    Given path recentPath
    When method get
    Then status 200
    And match response.items[*].assetId contains registerDomainA.assetId
    And match response.items[*].assetId !contains registerDomainB.assetId

    # list domain B — only its own item, not domain A's
    Given path recentPathB
    When method get
    Then status 200
    And match response.items[*].assetId contains registerDomainB.assetId
    And match response.items[*].assetId !contains registerDomainA.assetId

    # clear both
    Given path recentPath
    When method delete
    Then status 204

    Given path recentPathB
    When method delete
    Then status 204
