@ignore
Feature: Delete the domain's Vault configs with a given name, if any (helper).
  Usage: karate.call('classpath:iomete/helpers/secret/delete-vault-config.feature', { name: '...' })
  Fails if a matching config cannot be deleted.

  Scenario: find and delete
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/vault-configs'
    When method get
    Then status 200
    * def ids = response.filter(c => c.item.name == name).map(c => c.item.id)
    * karate.forEach(ids, function(id){ karate.call('classpath:iomete/helpers/secret/delete-vault-config-by-id.feature', { configId: id }) })
