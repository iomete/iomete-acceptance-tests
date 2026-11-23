@lock=spark
Feature: Create a compute with driver and executor, start it, then stop it

  Scenario: create a compute with one driver and one executor, start it, then stop it
    * url baseUrl
    * def computeName = 'karate-start-stop-compute-' + runId
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    # cleanup: delete compute if it exists from a previous run
    * def clearedCompute = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }

    # teardown: never leave this compute behind, pass or fail
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
      }
      """

    # create compute with one driver and one executor (singleNodeDeployment: false)
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)' }
    * def computeId = created.computeId

    # verify the compute is created and ACTIVE
    Given path computePath, computeId
    When method get
    Then status 200
    And match response.driverStatus == 'ACTIVE'
    And match response.nodeTypes.maxExecutors == 1
    And match response.nodeTypes.singleNodeDeployment == false

    # stop the compute
    Given path computePath, computeId, 'stop'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

    # wait until the driver is STOPPED
    * configure retry = { count: 30, interval: 10000 }
    Given path computePath, computeId
    And retry until response.driverStatus == 'STOPPED'
    When method get
    Then status 200

    # verify the compute is stopped
    And match response.driverStatus == 'STOPPED'
