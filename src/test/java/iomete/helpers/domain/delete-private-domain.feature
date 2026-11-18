@ignore
Feature: Delete a private domain a scenario left behind, with its catalogs and test users (plumbing).
  For cleanup-run-domain: a cancelled run skips the scenario's own teardown. No admin can list or
  delete a private domain's catalogs, so this signs in as its owner, deletes them, then deletes the
  domain as the admin. The scenarios name their users karate-priv-owner-<run id> and
  karate-priv-member-<run id>, so those are the owner signed in as and the users removed. An owner
  user an interrupted teardown already deleted is created again: ownership is kept by username.
  The scenarios create no computes, jobs or other runtimes in these domains.
  Call it with:
    karate.call('classpath:iomete/helpers/domain/delete-private-domain.feature', { domain: 'karate-priv-...' })
  Returns:
    removed  what it deleted, one line per item
    failed   what it could not delete, one line per item

  Scenario: delete the domain's catalogs as its owner, then the domain and the users
    * def removed = []
    * def failed = []
    * def ownerUser = 'karate-priv-owner-' + runId
    * def memberUser = 'karate-priv-member-' + runId
    * def adminHeaders = { 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }

    # sign in as the owner: a known password on an existing user, or a new user's temporary one
    * def password = 'Karate-' + java.util.UUID.randomUUID() + '!1'
    Given url baseUrl
    And path 'api/v1/admin/identity/users', ownerUser
    When method get
    * def ownerExists = responseStatus == 200
    * if (ownerExists) karate.call('classpath:iomete/helpers/user/set-password.feature', { username: ownerUser, password: password })
    * def recreated = ownerExists ? null : karate.call('classpath:iomete/helpers/user/create-user.feature', { username: ownerUser })
    * def login = call read('classpath:iomete/helpers/user/login.feature') { username: '#(ownerUser)', password: '#(ownerExists ? password : recreated.temporaryPassword)' }
    * def ownerHeaders = { Authorization: '#("Bearer " + login.accessToken)' }

    # the domain's own catalogs; a fresh login's domains are cached for a few seconds
    * def catalogsPath = 'api/v1/domains/' + domain + '/spark/settings/catalogs'
    * configure headers = ownerHeaders
    * configure retry = { count: 15, interval: 2000 }
    Given url baseUrl
    And path catalogsPath
    And retry until responseStatus != 403
    When method get
    * def owned = responseStatus == 200 ? response.items.filter(c => c.ownerDomainId == domain) : []
    * if (responseStatus != 200) failed.push('catalogs of domain ' + domain + ': listing as the owner answered ' + responseStatus)
    * def deleteCatalog = function(c){ var r = karate.http(baseUrl + '/' + catalogsPath + '/' + c.name).headers(ownerHeaders).delete(); if (r.status == 200 || r.status == 204 || r.status == 404) removed.push('catalog ' + c.name); else failed.push('catalog ' + c.name + ': ' + r.status) }
    * karate.forEach(owned, deleteCatalog)

    # the domain, as the admin
    * configure headers = adminHeaders
    Given url baseUrl
    And path 'api/v1/admin/domains', domain
    When method delete
    * if (responseStatus == 204) removed.push('domain ' + domain)
    * if (responseStatus != 204 && responseStatus != 400 && responseStatus != 404) failed.push('domain ' + domain + ': ' + responseStatus + ' ' + karate.toString(response))

    * karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: ownerUser })
    * karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: memberUser })
    * removed.push('users ' + ownerUser + ', ' + memberUser)
