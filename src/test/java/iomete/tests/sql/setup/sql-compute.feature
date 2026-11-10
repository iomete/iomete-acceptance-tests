@ignore
Feature: Shared compute for the iom-sql tests — invoked once per run via karate.callSingle.
  The custom image is an iom-sql specific: the V2 query API requires the async
  getFlightInfo + Flight auth changes. Arrow-fetch storage is never set here — the
  platform injects it from each data plane's storage report, and a pinned conf would
  override that with a bucket only one target can reach. The refresh-actions conf lets an
  admin reload the compute's access policies and tags through iom-sql
  (tests/sql/crawler-and-access-refresh.feature); without it that endpoint answers 501.

  Scenario: get or create the sql test computes
    # the domain and its namespace must exist before a compute can be created
    * karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domain })

    # The V2 compute is RUN-OWNED (named in karate-config.js under fixtures, dropped by
    # cleanup-run) and keyed by image too, so the two e2e legs of one run get their own.
    # The compat compute is pinned to spark:3.5.7-v3 regardless of the run's image, so it
    # stays fixed-name and long-lived (all runs share the one pre-V2 compute).
    * def newComputeName = fixtures.sqlCompute
    * def oldComputeName = compatCompute

    # New Spark compute (V2-compatible: HTTP events + Arrow Fetch, storage injected per plane)
    * def sqlComputeParams =
      """
      {
        name: '#(newComputeName)',
        image: '#(sparkImage)',
        sparkConf: { 'spark.iomete.arrow.flight.refreshActions.enabled': 'true' },
        driverType: 'karate-shared-driver',
        executorType: 'karate-shared-exec'
      }
      """
    * def result = call read('classpath:iomete/helpers/compute/create-compute.feature') sqlComputeParams
    * def computeName = result.computeName
    * def computeId = result.computeId
    # where the strategy put it (null = local) — callers pick their v1/v2 path by this
    * def computeDataPlane = result.computeDataPlane

    # before anything reads through it, so its audit events never meet a missing table
    * if (dataAccessAuditEnabled) karate.call('classpath:iomete/helpers/audit/create-audit-table.feature', { domain: domain, computeName: computeName, computeDataPlane: computeDataPlane })

    # Old Spark compute (pre-V2 image, no HTTP events, no Arrow Fetch). One scenario needs it,
    # and a whole warm compute for one scenario is capacity the overlapping runs want back, so
    # it is only built when the run asks for it (the nightly one does).
    * def oldComputeImage = imageRef('spark:3.5.7-v3')
    * def oldComputeParams = { name: '#(oldComputeName)', image: '#(oldComputeImage)' }
    * if (includeCompat) karate.call('classpath:iomete/helpers/compute/create-compute.feature', oldComputeParams)