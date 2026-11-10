@ignore
Feature: Remove one Spark property from a domain, leaving the others as they are.
  Call with:
    karate.call('classpath:iomete/helpers/domain/remove-spark-property.feature', { key: 'spark.karate.x' })
  A PUT replaces the whole list, so the current list is read first. Secret values come back masked,
  and sending the mask keeps the stored value. A no-op when the key is already gone.

  Scenario: drop the key from the domain's Spark properties
    Given url baseUrl
    And path 'api/v1/domains', domain, 'spark/settings/properties'
    When method get
    Then status 200
    * if (!response.some(p => p.key == key)) karate.abort()
    * def remaining = response.filter(p => p.key != key)

    Given path 'api/v1/domains', domain, 'spark/settings/properties'
    And request remaining
    When method put
    Then status 200
