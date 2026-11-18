@ignore
Feature: Create a private domain owned by a fresh user, and sign the owner in.
  A private domain's data is managed by its own owners only: no platform admin role, the super
  admin included, counts as one. So a scenario that acts as the owner needs a user of its own,
  which this creates (deleting a leftover of the same name first, since only a new user comes with
  a password), names as the domain's only owner through create-domain.feature, and signs in.
  Creating a private domain needs the `privateDomains` rollout flag on; callers make sure of it
  with enable-private-domains.feature first, since an abort here only ends the helper. The caller
  deletes the domain and the owner afterwards; cleanup-run-domain sweeps what a cancelled run left.
  Call it with:
    karate.call('classpath:iomete/helpers/domain/create-private-domain.feature',
                { domainId: 'karate-priv-<run id>-...', owner: 'karate-priv-owner-<run id>' })
  Returns:
    owner         the owner's username, lowercased as the platform stores it
    ownerHeaders  request headers that act as the owner

  Scenario: create the owner and the domain, then wait until the owner can reach it
    * def owner = owner.toLowerCase()
    * def cleared = call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(owner)' }
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(owner)' }
    * def createdDomain = call read('classpath:iomete/helpers/domain/create-domain.feature') { domainId: '#(domainId)', owner: '#(owner)', isPrivate: true }

    * def login = call read('classpath:iomete/helpers/user/login.feature') { username: '#(owner)', password: '#(created.temporaryPassword)' }
    * def ownerHeaders = { Authorization: '#("Bearer " + login.accessToken)' }

    # a user's domains are cached for a few seconds, so the owner may not reach the new domain at once
    * configure headers = ownerHeaders
    * configure retry = { count: 15, interval: 2000 }
    Given url baseUrl
    And path 'api/v1/domains', domainId, 'spark/settings/catalogs'
    And retry until responseStatus != 403
    When method get
    Then status 200
