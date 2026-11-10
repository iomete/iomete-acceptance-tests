@lock=spark
Feature: Query accelerator (Apache Comet) — an enabled compute actually routes execution through Comet.
  Acceptance smoke for the opt-in queryAcceleratorEnabled toggle. Comet ships only in Spark 4+ images,
  so this self-skips on older majors. It falls back to stock Spark SILENTLY, so "the flag persisted" and
  "a query ran" prove nothing on their own — the physical plan is the honest signal, and a real table is
  needed since a table-less EXPLAIN shows no Comet operators. The 400 rejections (pre-Spark-4, single-node)
  are the service's own validation and live in iom-cluster's ComputeServiceTest.

  Background:
    * if (sparkMajor < 4) karate.abort()
    * url baseUrl
    * def computePath = 'api/v2/domains/' + domain + '/compute'
    # scenario-owned and per run: a warm compute kept between runs holds spark node pool
    # capacity that the job scenarios need for their executors
    * def computeName = 'karate-accel-' + runId
    # no pinned arrow-fetch sparkConf: the platform injects it per plane (see sql-compute.feature)
    * def probeTable = 'spark_catalog.default.karate_accel_probe_' + runId
    * def runQuery = function(s){ return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: computeName, statement: s }).result }
    # a compute is reused as-is once it exists, so drop one an earlier run left behind rather
    # than testing one that was built without the accelerator
    * def clearedCompute = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }

    # the table drop stays fail-visible, since a leaked run-scoped table on a target that is not
    # rebuilt (dev/release) is worth surfacing. The compute goes either way: it outlives the
    # table and costs the node pool far more.
    * configure afterScenario =
      """
      function() {
        var error = null;
        try {
          runQuery('DROP TABLE IF EXISTS ' + probeTable);
        } catch (e) {
          error = e;
        }
        karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
        if (error) throw error;
      }
      """

  @spark4
  Scenario: a Comet-enabled compute boots and runs a query through Comet
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)', image: '#(sparkImage)', queryAcceleratorEnabled: true }

    Given path computePath
    When method get
    Then status 200
    * def compute = response.items.find(c => c.name == computeName)
    * match compute == '#notnull'
    * match compute.queryAcceleratorEnabled == true

    * runQuery('CREATE OR REPLACE TABLE ' + probeTable + ' (id INT, v INT) USING iceberg')
    * runQuery('INSERT INTO ' + probeTable + ' VALUES (1, 10), (2, 20), (1, 30)')

    # the proof: BOTH the scan and the aggregate run through Comet — a bare 'Comet' substring would
    # pass even if one operator fell back to stock Spark
    * def plan = runQuery('EXPLAIN FORMATTED SELECT id, SUM(v) AS s FROM ' + probeTable + ' GROUP BY id')
    * def planText = karate.toString(plan.values)
    * match planText contains 'CometIcebergNativeScan'
    * match planText contains 'CometHashAggregate'

    # and it executes correctly on the Comet compute
    * def total = runQuery('SELECT SUM(v) AS s FROM ' + probeTable)
    * match total.values == [60]
