# Write IOMETE Acceptance Test

This skill guides you in writing Karate acceptance tests for the IOMETE platform. The tests are published to customers, so they must be customer-facing and clean up after themselves.

## Repository Structure

- **`src/test/java/iomete/helpers/`** — Reusable building blocks for services (compute, query, user, security, catalog, job, etc.). These are called by tests, not run directly.
- **`src/test/java/iomete/tests/<service>/`** — The actual test features, organized by service area (compute, sql, job, data-security, identity, catalog, etc.).
- **`custom-tests/`** — Customer's own tests (not in this repo, but mentioned for context).

## Key Conventions

### 1. Use `runId` for unique names
Every test-created resource must carry the `runId` from `karate-config.js` to avoid conflicts between concurrent runs:
```gherkin
* def computeName = 'karate-my-compute-' + runId
* def userName = 'karate-user-' + runId
```

### 2. Use `@lock` tags for resource isolation
Every feature must start with a `@lock=<lane>` tag. Lanes control concurrency:
- `@lock=spark` — Tests that start long-lived Spark pods (computes, Jupyter containers, event streams)
- `@lock=job` — Tests that run job runs (including streaming jobs)
- `@lock=sql` — Tests that query the shared SQL compute
- `@lock=security` — Tests that query the security compute under policies
- `@lock=api` — Tests that only make control-plane API calls
- `@lock=maintenance` — Tests that change maintenance catalog config

```gherkin
@lock=spark
Feature: My compute test
```

Multiple lanes can be specified with commas: `@lock=spark,maintenance`

### 3. Clean up what you create
Every scenario must delete resources it creates. Use `afterScenario` teardown:
```gherkin
* configure afterScenario =
  """
  function() {
    karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
  }
  """
```

Or clean up at the end of the scenario before teardown.

### 4. Use existing helpers
Don't duplicate logic. Use helpers from `classpath:iomete/helpers/`:
- `compute/create-compute.feature` — Create or reuse a compute, wait until it can run SQL
- `compute/delete-compute.feature` — Delete a compute by name
- `query/run-query.feature` — Run a SQL query against a compute
- `domain/ensure-domain.feature` — Ensure a domain exists
- `user/create-user.feature` — Create a user
- `job/run-job.feature` — Run a job

### 5. Customer-facing only
- No internal hostnames, registries, ticket numbers, team channels, or incident history in code or comments
- No credentials in code or CI
- Keep explanations in plain words, not internal jargon

## Test Feature Template

```gherkin
@lock=<lane>
Feature: Short description of what this feature tests

  Optional: A longer description explaining the purpose and what it validates.

  Background:
    * url baseUrl
    * def computeName = 'karate-<descriptive-name>-' + runId
    * def computePath = 'api/v2/domains/' + domain + '/compute'

    # cleanup: delete if exists from previous run
    * def clearedCompute = call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }

    # teardown: never leave resources behind
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName });
      }
      """

  Scenario: what this scenario does
    # Step 1: create resource
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)' }
    * def computeId = created.computeId

    # Step 2: verify
    Given path computePath, computeId
    When method get
    Then status 200
    And match response.driverStatus == 'ACTIVE'

    # Step 3: perform action
    Given path computePath, computeId, 'stop'
    When method post
    Then assert responseStatus >= 200 && responseStatus < 300

    # Step 4: wait and verify result
    * configure retry = { count: 30, interval: 10000 }
    Given path computePath, computeId
    And retry until response.driverStatus == 'STOPPED'
    When method get
    Then status 200
```

## Common Patterns

### Creating a compute
```gherkin
* def created = call read('classpath:iomete/helpers/compute/create-compute.feature') {
  name: '#(computeName)',
  singleNode: true,
  image: '#(sparkImage)'
}
```

### Running a query
```gherkin
* def result = call read('classpath:iomete/helpers/query/run-query.feature') {
  domain: domain,
  computeName: computeName,
  statement: 'SELECT 1'
}
```

### Waiting for a state
```gherkin
* configure retry = { count: 30, interval: 10000 }
Given path computePath, computeId
And retry until response.driverStatus == 'ACTIVE'
When method get
Then status 200
```

### Using the shared SQL compute
```gherkin
* def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
* def computeId = sqlCompute.computeId
* def computeName = sqlCompute.computeName
```

## Referencing OpenAPI Specs

The IOMETE API is documented via OpenAPI specs available at your install's `/openapi/` endpoints. Use these to understand available endpoints, request/response schemas, and required parameters:

### Available Specs
- `/openapi/core?format=json` — Data plane management, autoscaling, control plane health
- `/openapi/cluster?format=json` — Compute clusters, bundles, webhooks, SQL queries
- `/openapi/iam?format=json` — Identity & Access Management, policies, roles, permissions
- `/openapi/sql?format=json` — SQL query execution, worksheets, collaboration
- `/openapi/catalog?format=json` — Catalog metadata, classification tags, data products
- `/openapi/rest-catalog?format=json` — Iceberg REST catalog API, S3 signing
- `/openapi/maintenance?format=json` — Catalog maintenance operations, compaction

### Accessing the Specs
Use `curl` with your access token:
```bash
curl -H "Authorization: Bearer <your-token>" \
  https://<your-iomete-url>/openapi/cluster?format.json
```

Or view the interactive Swagger UI at:
```
https://<your-iomete-url>/openapi/ui/
```

### Using Specs in Tests
1. Fetch the spec to understand the endpoint structure
2. Look up the path, method, request body schema, and response schema
3. Map the schema fields to your Karate test steps
4. Use the spec's example values or constraints for assertions

Example: If the spec shows a POST endpoint with a required `name` field and optional `description`:
```gherkin
Given path 'api/v2/domains', domain, 'compute'
And request { name: '#(computeName)', description: 'test compute' }
When method post
Then status 201
And match response.name == '#(computeName)'
```

## Running Your Test

From the repo root:
```bash
make test-one FEATURE=src/test/java/iomete/tests/compute/my-test.feature
```

Or by line number for a specific scenario:
```bash
make test-one FEATURE=src/test/java/iomete/tests/compute/my-test.feature:25
```

## Important Notes

1. **This is a published copy** — Changes to tests here are overwritten by IOMETE releases. Fix tests in the main IOMETE repository instead.
2. **README and AGENTS.md are maintained here** — Keep documentation in sync with the tests.
3. **No CI against real installs** — Never add CI that runs against a real IOMETE install from this repository.
4. **Test isolation** — Scenarios must not rely on each other; each sets up what it needs.
