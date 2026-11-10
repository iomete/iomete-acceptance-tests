@ignore
Feature: Grant a user access to run queries on a compute (via the bundle it is in).
  Domain membership/roles are not enough to reach a compute — access is a bundle grant on
  the compute's bundle (resolved by find-compute-bundle.feature). Deleting the user does
  not remove the grant; revoke-bundle-grants.feature does. Call it with:
    karate.call('classpath:iomete/helpers/compute/grant-compute-access.feature',
                { username: 'karate-security-user', computeName: 'karate-security', domain: 'karate' })
  Idempotent: it removes any existing grant for the user, then adds VIEW/EXECUTE/CONSUME.

  Scenario: resolve the compute's bundle and grant COMPUTE access
    * def found = call read('classpath:iomete/helpers/compute/find-compute-bundle.feature') { computeName: '#(computeName)', domain: '#(domain)' }
    * def bundleId = found.bundleId
    * match bundleId == '#notnull'

    # idempotency: adding a duplicate grant errors, so clear any existing grant first
    Given url baseUrl
    And path 'api/v1/bundles', bundleId, 'permissions'
    And request { actorType: 'USER', actorId: '#(username)' }
    When method delete
    Then assert responseStatus == 204 || responseStatus == 200 || responseStatus == 404

    # build the grant with the username as a dynamic map key
    * def grant = { COMPUTE: { users: {}, groups: {} } }
    * eval grant.COMPUTE.users[username] = ['VIEW', 'EXECUTE', 'CONSUME']

    Given url baseUrl
    And path 'api/v1/bundles', bundleId, 'permissions'
    And request grant
    When method post
    Then assert responseStatus == 204 || responseStatus == 200
