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
    # emptyDir, since restricted namespaces refuse hostPath; volumes have no name, so a
    # run-derived size keeps them unique and a tag marks the run's own
    * def maxSize = 100 + hashString(runId) % 1000
    * def volumeTag = 'karate-volume'
    * def computeName = 'karate-volume-compute-' + runId
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    # a compute is reused as-is once it exists, so drop any left behind by an earlier run
    # rather than testing one that was built without the volume
    * def clearedCompute = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }
    * def clearedVolume = call read('classpath:iomete/helpers/volume/delete-run-volume.feature') { tag: '#(volumeTag)' }

    # drop the compute and volume here rather than at the end, which would miss the failure paths
    * configure afterScenario =
      """
      function() {
        // separate tries, so the volume still goes when the compute delete fails
        try { karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName }); } catch (e) { karate.log('compute teardown failed:', e.message); }
        try { karate.call('classpath:iomete/helpers/volume/delete-run-volume.feature', { tag: volumeTag }); } catch (e) { karate.log('volume teardown failed:', e.message); }
      }
      """

  Scenario: the compute comes up with the volume attached and keeps working after the volume is deleted
    # the run's own volume was cleared above, so a 409 is someone else's with the same size
    Given path volumesPath
    And request { type: 'EMPTY_DIR', maxSize: '#(maxSize)', resourceTags: [{ key: '#(volumeTag)', value: '#(runId)' }] }
    When method post
    * if (responseStatus == 409) karate.fail('An EMPTY_DIR volume of ' + maxSize + 'Gi already exists and is not this run\'s; rerun with another IOMETE_RUN_ID')
    Then status 200
    * def volumeId = response.id

    # the helper waits for ACTIVE and proves the compute can really run SQL
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)', volumeId: '#(volumeId)', singleNode: true }

    # the platform reports back the volume we asked for
    Given path computePath, created.computeId
    When method get
    Then status 200
    And match response.volumeId == volumeId

    # the running driver got the volume's size limit, which only an attached volume sets.
    # The key is backquoted, since SET refuses one with hyphens otherwise.
    # v2 goes through the driver's Arrow Flight listener, which can come up later, so resubmit briefly
    * def sizeLimitConf = 'spark.kubernetes.executor.volumes.emptyDir.spark-local-dir-1.options.sizeLimit'
    * def readSizeLimit =
      """
      function() {
        var deadline = java.lang.System.currentTimeMillis() + 3 * 60 * 1000;
        while (true) {
          try {
            return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { computeName: computeName, statement: 'SET `' + sizeLimitConf + '`', retryCount: 10 });
          } catch (e) {
            if (java.lang.System.currentTimeMillis() > deadline) throw e;
            karate.log('v2 submit not ready yet, retrying:', e.message);
            java.lang.Thread.sleep(5000);
          }
        }
      }
      """
    * def conf = readSizeLimit()
    * karate.log('size limit conf:', conf.result)
    And match conf.result.values == ([sizeLimitConf, maxSize + 'Gi'])

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
