---
name: write-acceptance-test
description: Write a Karate acceptance test for an IOMETE install in custom-tests/. Use when asked to add, write or extend an acceptance test, or to check a feature of an IOMETE install end to end.
---

# Write an IOMETE acceptance test

The rules live in the repository's own docs. Read them first; this skill only points at them and adds examples:

- [README.md](../../../README.md): where your own tests go, how to run them, the settings.
- [CONTRIBUTING.md](../../../CONTRIBUTING.md): the test-writing rules (run id naming, cleanup).
- [AGENTS.md](../../../AGENTS.md): what this repository is and what must never go in it.

If anything here disagrees with those files, they win.

## Where the test goes

Write new tests in `custom-tests/`, starting from `custom-tests/example.feature`. Each IOMETE release replaces everything under `src/test/java/iomete/tests`, so a test written there is lost at the next release. To change an IOMETE test, follow CONTRIBUTING.md instead.

A test in `custom-tests/` can use the suite's settings (`baseUrl`, `domain`, `runId`, ...) and its helpers through `call read('classpath:iomete/helpers/...')`.

## The `@lock` lane

The first line of every feature is a `@lock=<lane>` tag. The suite refuses to start when a lane is missing or unknown. The valid lanes are the `LANES` set in `src/test/java/iomete/ApiTest.java`:

`spark`, `job`, `job2`, `stream`, `sql`, `security`, `maintenance`, `api`

- A test that only calls the API uses `@lock=api` (as the README says).
- Otherwise pick the lane of the closest existing test under `src/test/java/iomete/tests/`, for example `grep -rl '^@lock=' src/test/java/iomete/tests/compute`. A test that starts its own compute uses `spark`; the event stream ingest tests use `stream`.
- Several lanes are joined with commas: `@lock=spark,maintenance`.

## Cleanup

Name everything the test creates with `runId`, and delete it in an `afterScenario`. Steps after a failed assertion never run, so cleanup at the end of a scenario is not enough. Register the teardown before creating anything:

```gherkin
* def computeName = 'karate-my-compute-' + runId
* configure afterScenario =
  """
  function() {
    karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
  }
  """
```

## Template

A test that brings its own compute, stops it and checks that it stopped. It follows `src/test/java/iomete/tests/compute/compute-lifecycle.feature`.

```gherkin
@lock=spark
Feature: Short description of what this feature checks

  Background:
    * url baseUrl
    * def computeName = 'karate-my-compute-' + runId
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    # an existing compute is reused as-is, so drop one an earlier run left behind
    * def cleared = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }

    # teardown: runs even when a step fails
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
      }
      """

  Scenario: a running compute stops on request
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)' }

    Given path computePath, created.computeId, 'stop'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

    * configure retry = { count: 30, interval: 10000 }
    Given path computePath, created.computeId
    And retry until response.driverStatus == 'STOPPED'
    When method get
    Then status 200
```

## Helpers

Use a helper rather than calling the API yourself where one exists. Each helper's header says what it takes and returns. Some you will need often:

- `compute/create-compute.feature`: create or reuse a compute and wait until it runs SQL. Returns `computeName`, `computeId` and `computeDataPlane`.
- `compute/delete-compute.feature`: delete a compute by name. Does nothing if it is not there.
- `query/run-query.feature` (V1) and `query/run-query-v2.feature` (V2, returns the result): run a SQL statement. V1 cannot reach a compute on a remote data plane, so pick the helper with `queryFeatureFor(computeDataPlane)` instead of naming one.
- `user/create-user.feature`, `job/run-job.feature`, `domain/ensure-domain.feature`.

Arguments to `call` must stay on one line. For a longer argument, define it first with a triple-quoted block:

```gherkin
* def computeArgs =
  """
  { name: '#(computeName)', singleNode: true }
  """
* def created = call read('classpath:iomete/helpers/compute/create-compute.feature') computeArgs
```

Running a query on a compute the test created:

```gherkin
* def queryFeature = queryFeatureFor(created.computeDataPlane)
* def query = karate.call(queryFeature, { computeName: computeName, statement: 'SELECT 1 AS one' })
```

## Finding endpoints in the OpenAPI specs

Each backend service serves its OpenAPI spec at `/openapi/<service>?format=json`, to an authenticated caller only. The services are `core`, `cluster`, `iam`, `sql`, `catalog`, `rest-catalog` and `maintenance` (see `src/test/java/iomete/helpers/save-openapi-specs.feature`).

```bash
curl -H "Authorization: Bearer <your-token>" \
  "https://<your-iomete-url>/openapi/cluster?format=json"
```

Use a spec to find an endpoint's path, method and body. Before calling an endpoint yourself, check that no helper covers it already. Creating a compute, for example, needs more than the spec shows (a namespace, node types, reuse on 409), so always go through `create-compute.feature` for that.

## Running the test

```bash
make test-one FEATURE=custom-tests/my-test.feature      # one feature
make test-one FEATURE=custom-tests/my-test.feature:25   # the scenario at that line
make test-one FEATURE=custom-tests                      # all your own tests
```

Run `make clean` after adding, moving or renaming a feature.
