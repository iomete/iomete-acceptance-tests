@ignore
Feature: Make a user a domain member and grant it domain-level permissions.
  Permissions are granted on the domain's root bundle, which is where the DOMAIN asset type
  lives. Call it with:
    karate.call('classpath:iomete/helpers/domain/grant-domain-permissions.feature',
                { username: 'karate-secret-reader', permissions: ['LIST_SECRETS'] })
  Membership comes first: a grant on a user that is not a member of the domain buys it
  nothing. Where `domainBundleAuth` is off the domain has no bundle to grant on, so this
  applies membership only and returns without a `rootBundleId`, so a caller that needs the
  permission itself must gate its scenario on `domainBundleAuth`. Returns:
    domainId      the domain's id (the config holds its name)
    rootBundleId  the bundle the grant was written to (absent when domainBundleAuth is off)

  Scenario: add the user to the domain, then grant it the permissions
    * def username = username.toLowerCase()

    # the config carries the domain name; the members and bundle APIs want its id
    Given url baseUrl
    And path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domainRecord = response.find(d => d.name == domain)
    * match domainRecord == '#notnull'
    * def domainId = domainRecord.id

    # 204 is what this actually answers, despite the 201 its own spec advertises;
    # 409 = already a member, which is fine
    Given url baseUrl
    And path 'api/v1/admin/domains', domainId, 'members'
    And request [ { type: 'USER', value: '#(username)' } ]
    When method post
    Then assert responseStatus == 201 || responseStatus == 204 || responseStatus == 409

    # membership is all there is to grant without domain bundles; the domain record carries
    # no `bundle` at all then, so stop before reading one
    * if (!domainBundleAuth) karate.abort()

    * def rootBundleId = domainRecord.bundle.bundleId
    * match rootBundleId == '#notnull'

    # idempotency: adding a duplicate grant errors, and deleting a user does not take its
    # grant rows with it, so clear any existing grant first
    Given url baseUrl
    And path 'api/v1/bundles', rootBundleId, 'permissions'
    And request { actorType: 'USER', actorId: '#(username)' }
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200 || responseStatus == 404

    # the username is a key here, and embedded expressions only resolve in values
    * def permissionBody = { DOMAIN: { users: {}, groups: {} } }
    * eval permissionBody.DOMAIN.users[username] = permissions

    Given url baseUrl
    And path 'api/v1/bundles', rootBundleId, 'permissions'
    And request permissionBody
    When method post
    Then assert responseStatus == 204 || responseStatus == 200
