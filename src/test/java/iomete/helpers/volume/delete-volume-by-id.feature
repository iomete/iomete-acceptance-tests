@ignore
Feature: Delete one volume by id (plumbing).
  karate.call('classpath:iomete/helpers/volume/delete-volume-by-id.feature', { volumeId: '...' })

  A missing volume answers 404, which counts as done.

  Scenario: delete the volume
    Given url baseUrl
    And path 'api/v1/admin/volumes', volumeId
    When method delete
    Then assert responseStatus == 204 || responseStatus == 404
