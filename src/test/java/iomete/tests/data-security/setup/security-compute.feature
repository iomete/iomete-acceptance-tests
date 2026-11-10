@ignore
Feature: Compute for the security tests — invoked once per run via karate.callSingle.
  Owned by the security suite so it can evolve independently of the iom-sql compute
  (e.g. swapping to a per-user-enforcing image to actually exercise Ranger policies).
  Uses the same V2-compatible image the SQL suite relies on: the V2 query API needs the
  async getFlightInfo + Flight auth changes. Arrow-fetch storage is injected by the
  platform per data plane, not pinned here (see sql-compute.feature).

  Kept separate from the iom-sql compute on purpose: sharing one breaks the SQL suite. See
  the Compute section in AGENTS.md.

  Scenario: get or create the security test compute
    # the domain and its namespace must exist before a compute can be created
    * karate.callSingle('classpath:iomete/helpers/domain/ensure-domain.feature', { domain: domain })

    # run-owned (named in karate-config.js under fixtures, dropped by cleanup-run) and keyed
    # by image too, so the two e2e legs of one run get their own (see sql-compute)
    * def computeName = fixtures.securityCompute

    # arrow-fetch storage is injected per plane — never pin it (see sql-compute.feature)
    * def securityComputeParams =
      """
      {
        name: '#(computeName)',
        image: '#(sparkImage)'
      }
      """
    * def result = call read('classpath:iomete/helpers/compute/create-compute.feature') securityComputeParams
    * def computeName = result.computeName
    # where the strategy put it (null = local) — callers pick their v1/v2 path by this
    * def computeDataPlane = result.computeDataPlane
