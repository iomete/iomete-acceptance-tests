@ignore
Feature: Remove this run's tagged volume if it is still there (plumbing).
  Teardown helper, safe to call when the volume is already gone:
    karate.call('classpath:iomete/helpers/volume/delete-run-volume.feature', { tag: 'karate-volume' })

  Deletes every volume carrying the tag with this run's id as its value. Volumes have no name,
  so the tag is the only thing that says a volume is the run's own.

  Scenario: delete the run's volumes, or do nothing if there are none
    Given url baseUrl
    And path 'api/v1/admin/volumes'
    When method get
    Then status 200
    * def owned = response.filter(v => (v.resourceTags || []).some(t => t.key == tag && t.value == runId))
    * def deleteOne = function(v) { return karate.call('classpath:iomete/helpers/volume/delete-volume-by-id.feature', { volumeId: v.id }) }
    * karate.forEach(owned, deleteOne)
