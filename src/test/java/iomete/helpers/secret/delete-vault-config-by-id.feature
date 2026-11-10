@ignore
Feature: Delete one Vault config by id (helper).
  Usage: karate.call('classpath:iomete/helpers/secret/delete-vault-config-by-id.feature', { configId: '...' })

  Scenario: delete it
    Given url baseUrl
    And path 'api/v1/domains/' + domain + '/vault-configs', configId
    When method delete
    # 404 means it is already gone, which is what the caller wanted.
    Then assert responseStatus == 204 || responseStatus == 404
