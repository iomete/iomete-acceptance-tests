@ignore
Feature: Revoke the bundle grants a user was given, before the user is deleted.
  Deleting a user does not take its grant rows with it, so a user the suite onboarded leaves
  an orphan actor in shared bundles unless its grants are revoked first. Undoes what
  grant-compute-access.feature (computeName) and grant-domain-permissions.feature (domainRoot)
  granted. Call it with:
    karate.call('classpath:iomete/helpers/user/revoke-bundle-grants.feature',
                { username: 'karate-security-user', computeName: 'karate-security', domainRoot: false })
  A no-op for a compute that is already gone, a grant that is not there, and the domain root
  where domainBundleAuth is off (there is no domain bundle then).

  Scenario: revoke the user's grant on each bundle
    * def username = username.toLowerCase()
    * def computeName = karate.get('computeName', null)
    * def domainRoot = karate.get('domainRoot', false)
    * def bundleIds = []

    * if (computeName) bundleIds.push(karate.call('classpath:iomete/helpers/compute/find-compute-bundle.feature', { computeName: computeName, domain: domain }).bundleId)

    # the config carries the domain name; the root bundle hangs off the domain record, which
    # has no bundle at all where domainBundleAuth is off
    Given url baseUrl
    And path 'api/v1/admin/domains'
    When method get
    Then status 200
    * def domainRecord = response.find(d => d.name == domain)
    * if (domainRoot && domainRecord && domainRecord.bundle) bundleIds.push(domainRecord.bundle.bundleId)

    * def revoke =
      """
      function(bundleId) {
        if (!bundleId) return;
        karate.call('classpath:iomete/helpers/user/revoke-bundle-grant.feature', { bundleId: bundleId, username: username });
      }
      """
    * karate.forEach(bundleIds, revoke)
