@ignore
Feature: Register the suite's own small node types (plumbing).
  The stock types are sized for real workloads, so overlapping runs do not fit the test
  environment's namespace quota. Registered once per run, shared and never deleted:
    karate.callSingle('classpath:iomete/helpers/compute/ensure-node-types.feature')

  CPU is a request only (the platform sets no CPU limit on Spark pods): it gates
  scheduling and throttles nothing, and measured usage stays well under half of 750m,
  so a driver+executor pair fits small planes where 1500m each could not schedule.
  Memory is request=limit and sizes the JVM heap, so it stays where it is.

  Scenario: register the missing ones, update the ones whose sizes drifted
    # memory in MB, cpu in millicores; nodeTypeCpu/nodeTypeMemory override them for a small target
    * def cpu = function(dflt){ return nodeTypeCpu > 0 ? nodeTypeCpu : dflt }
    * def mem = function(dflt){ return nodeTypeMemory > 0 ? nodeTypeMemory : dflt }
    * def sharedCpu = function(dflt){ return sharedComputeCpu > 0 ? sharedComputeCpu : cpu(dflt) }
    * def wanted =
      """
      [
        { name: 'karate-xs', description: 'iomete-api-testing-suite: job runs', memory: '#(mem(2048))', cpu: '#(cpu(1000))', spot: false, components: ['DRIVER', 'EXECUTOR'] },
        { name: 'karate-driver', description: 'iomete-api-testing-suite: compute drivers', memory: '#(mem(3072))', cpu: '#(cpu(750))', spot: false, components: ['DRIVER'] },
        { name: 'karate-exec', description: 'iomete-api-testing-suite: compute executors', memory: '#(mem(2048))', cpu: '#(cpu(750))', spot: false, components: ['EXECUTOR'] },
        { name: 'karate-shared-driver', description: 'iomete-api-testing-suite: shared SQL compute driver', memory: '#(mem(3072))', cpu: '#(sharedCpu(750))', spot: false, components: ['DRIVER'] },
        { name: 'karate-shared-exec', description: 'iomete-api-testing-suite: shared SQL compute executor', memory: '#(mem(2048))', cpu: '#(sharedCpu(750))', spot: false, components: ['EXECUTOR'] },
        { name: 'karate-jupyter', description: 'iomete-api-testing-suite: Jupyter containers', memory: 1024, cpu: 500, spot: false, components: ['DRIVER'] }
      ]
      """

    Given url baseUrl
    And path 'api/v1/admin/node-types'
    When method get
    Then status 200
    * def have = response
    * def missing = wanted.filter(t => !have.find(x => x.name == t.name))
    * def registered = call read('classpath:iomete/helpers/compute/register-node-type.feature') missing

    # a size change reaches environments where the types already exist only through this update
    * def drifted = wanted.filter(t => { var h = have.find(x => x.name == t.name); return h && (h.cpu != t.cpu || h.memory != t.memory) })
    * def updated = call read('classpath:iomete/helpers/compute/update-node-type.feature') drifted
