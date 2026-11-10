@ignore
Feature: Make the run's user an owner of a domain, if it is not one already (helper).
  Usage: karate.call('classpath:iomete/helpers/domain/ensure-domain-owner.feature', { domain: '...' })

  Some calls are allowed only for a domain owner, even to a platform admin. A domain update
  replaces the whole owner list, so this reads the domain and sends it back with the user added.
  It never removes an owner, and the ownership is never undone: other runs share the domain.
  The read and the write are not atomic, so an owner someone adds by hand in between is lost.

  Scenario: add the owner
    Given url baseUrl
    And path 'api/v1/user'
    When method get
    Then status 200
    # owners are usernames; the owner check compares them exactly (only saving is case-insensitive)
    * def userId = response.username

    Given url baseUrl
    And path 'api/v1/admin/domains', domain
    When method get
    Then status 200
    * def current = response
    # Where ownership lives on the domain's bundle (the response then carries a bundle), the owners
    # list is not what the owner check reads, so editing it would change data and prove nothing.
    * if (current.bundle) karate.fail('domain ' + domain + ' takes its owners from its bundle, which this helper does not set')
    * if (current.owners.indexOf(userId) >= 0) karate.abort()

    Given url baseUrl
    And path 'api/v1/admin/domains', domain
    And request { name: '#(current.name)', description: '#(current.description)', colorHex: '#(current.colorHex)', owners: '#(current.owners.concat([userId]))' }
    When method put
    Then status 200
    And match response.owners contains userId
