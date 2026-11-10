@lock=spark
Feature: Volumes, a volume attached to a compute is wired in and survives being deleted

  Volumes back Spark's scratch storage (shuffle, spill, cache) rather than a user-facing
  file path, so there is nothing to read or write at the SQL level. What the platform can
  be held to is that a compute asking for a volume actually gets provisioned with it, and
  that deleting the volume afterwards is the documented soft delete that leaves running
  workloads alone.

  Both halves share one compute, since a cold start costs minutes and the delete only
  means anything against a compute that is already up and serving queries. Reaching ACTIVE
  is not enough on its own: it only says the control plane thinks the pod is up, so the
  compute is asked to run real SQL on both sides of the delete.

  Background:
    * url baseUrl
    * def volumesPath = 'api/v1/admin/volumes'
    # keyed per run like the compute: this scenario DELETES the volume, so a shared one
    # would be pulled out from under a concurrent run halfway through
    * def hostPath = '/mnt/karate-' + runId
    * def computeName = 'karate-volume-compute-' + runId
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    # a compute is reused as-is once it exists, so drop any left behind by an earlier run
    # rather than testing one that was built without the volume
    * def clearedCompute = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }

    # a leaked compute holds node-pool capacity until someone deletes it, so drop it
    # here rather than at the end of the scenario, which would miss the failure paths
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
      }
      """

  Scenario: the compute comes up with the volume attached and keeps working after the volume is deleted
    # create if missing — 409 means an earlier run left one behind with the same type and
    # path, which is fine; the id is read off the listing either way
    Given path volumesPath
    And request { type: 'HOST_PATH', hostPath: '#(hostPath)' }
    When method post
    Then assert responseStatus == 200 || responseStatus == 409

    Given path volumesPath
    When method get
    Then status 200
    * def volume = response.find(v => v.type == 'HOST_PATH' && v.hostPath == hostPath)
    * match volume == '#notnull'
    * def volumeId = volume.id

    # the helper waits for ACTIVE and proves the compute can really run SQL
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)', volumeId: '#(volumeId)', singleNode: true }

    # the platform reports back the volume we asked for
    Given path computePath, created.computeId
    When method get
    Then status 200
    And match response.volumeId == volumeId

    # delete the volume out from under the running compute
    Given path volumesPath, volumeId
    When method delete
    Then status 204

    # the compute is left running, and still actually usable
    Given path computePath, created.computeId
    When method get
    Then status 200
    And match response.driverStatus == 'ACTIVE'

    # v1 cannot reach a compute on a remote data plane, so follow the path the warm-up used
    * def queryFeature = queryFeatureFor(created.computeDataPlane)
    * def query = karate.call(queryFeature, { computeName: computeName, statement: 'SELECT 1 AS one' })

    # the compute is dropped by afterScenario, so it goes even if the steps above fail
