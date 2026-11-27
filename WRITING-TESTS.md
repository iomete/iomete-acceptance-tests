# Writing a test

How to add tests of your own to the suite. The tests are [Karate](https://karatelabs.github.io/karate/) `.feature` files. They call the IOMETE API and check the responses.

## Where your test goes

Put your tests in `custom-tests/`. IOMETE releases replace everything under `src/` but never touch `custom-tests/`, so a test you put anywhere else is lost at the next upgrade.

If an IOMETE test is wrong, don't edit it here. Open an issue instead (see [CONTRIBUTING.md](CONTRIBUTING.md)).

Start by copying `custom-tests/example.feature`:

```gherkin
@lock=api
Feature: Example of your own test

  Background:
    * url baseUrl

  Scenario: the domains can be listed
    Given path 'api/v1/admin/domains'
    When method get
    Then status 200
    And match response[*].name contains domain
```

## The shape of a test

```gherkin
@lock=api                                  # required: what the test may run next to
Feature: <area>, <what is checked>          # one line saying what works

  A short description of what the test proves and why.

  Background:                               # runs before every scenario
    * url baseUrl
    * def name = 'karate-<what>-' + runId   # every name carries the run id
    * configure afterScenario = ...          # cleanup, pass or fail

  Scenario: <the behavior, in plain words>
    Given path '...'
    And request { ... }
    When method post
    Then status 201
    And match response == { ... }
```

Keep each feature to one area and each scenario to one behavior. Name a scenario after what it shows, for example *"an added user is listed as a domain member"*, not after the endpoint it calls.

## The `@lock` tag

Every feature needs a `@lock` tag on its first line. The suite won't start if one is missing or misspelled. Features with the same lock run one at a time, and features with different locks run in parallel. Pick the lock that matches what your test uses:

| Lock | Use it when the test |
|---|---|
| `api` | only calls the API and starts nothing |
| `sql` | runs SQL on the suite's shared compute |
| `spark` | starts its own compute, Jupyter container or other Spark workload |
| `job`, `job2` | runs Spark jobs |
| `stream` | uses event streams |
| `security` | applies data security policies |
| `maintenance` | runs table maintenance |

If you aren't sure, use `api` for API-only tests and `spark` for anything that starts something.

## What every test can use

The suite's settings set these values for every feature:

| Name | What it is |
|---|---|
| `baseUrl` | Your IOMETE console address |
| `domain` | The domain the run works in |
| `runId` | A short id for this run. Put it in every name you create |
| `token` | The admin access token. Every request sends it unless you change the headers |
| `sparkImage` | The Spark image the run tests |
| `platformVersion` | Your IOMETE version |
| `platformAtLeast('4.0.2')` | `true` if your install is at least that version |
| `platformChangesAllowed()` | `true` if `IOMETE_ALLOW_PLATFORM_CHANGES=true` |

Requests are sent as the admin. To act as another user, set the headers to that user's token (see [Acting as another user](#acting-as-another-user)).

## Rules

1. **Name everything after the run.** Use `'karate-<what>-' + runId` for platform objects and `'karate_<what>_' + runId` for SQL names. Then two runs can't collide, and `make cleanup` can find whatever is left behind.
2. **Clean up, pass or fail.** Register the cleanup in an `afterScenario` *before* you create anything, so it still runs if the test fails halfway.
3. **Start from a clean state.** Delete anything an earlier run may have left before you create it.
4. **Never hard-code an environment.** Don't put hostnames, users or credentials in a test. Use `baseUrl`, `domain` and settings read from the environment.
5. **Check the result, not just the status.** Read back what you created, or run the query and compare the rows.
6. **Skip, don't fail, when a feature isn't there.** See [Skipping](#skipping).
7. **Cover the main flow end to end.** Don't try to cover every edge case.

## Cleanup

```gherkin
  Background:
    * url baseUrl
    * def username = 'karate-my-user-' + runId

    # registered before the user exists, so a failed setup still cleans up
    * configure afterScenario =
      """
      function() {
        karate.call('classpath:iomete/helpers/user/delete-user.feature', { username: username });
      }
      """

    # remove anything an earlier run left behind, then create it fresh
    * call read('classpath:iomete/helpers/user/delete-user.feature') { username: '#(username)' }
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(username)' }
```

The delete helpers do nothing when the object is already gone, so you can call them safely at the start and the end.

## Reusing the suite's helpers

Helpers in `src/test/java/iomete/helpers/` handle the common setup and cleanup. Call them with `call read('classpath:iomete/helpers/...')` or `karate.call(...)`. Each helper's header explains what it takes and what it returns. Commonly used ones:

| Helper | What it does |
|---|---|
| `user/create-user.feature`, `user/delete-user.feature` | Create or remove a user. Returns its temporary password |
| `user/set-password.feature`, `user/add-roles.feature` | Give a user a known password or admin roles |
| `user/get-access-token.feature` | Log in as a user and get an access token for them (they need a password and an admin role) |
| `group/create-group.feature`, `group/delete-group.feature` | Create or remove a group |
| `compute/create-compute.feature` | Create a compute and wait until it can run SQL |
| `compute/delete-compute.feature` | Remove a compute by name |
| `query/run-query-v2.feature` | Run SQL as the admin and return the result. Fails if the query fails |
| `query/run-query-v2-as.feature` | Run SQL as another user and return the final status, for checking that access is denied |
| `job/create-job.feature`, `job/run-job.feature`, `job/delete-job.feature` | Create, run and remove a Spark job |
| `secret/delete-secret.feature` | Remove a secret |
| `security/create-policy.feature`, `security/delete-policy.feature` | Create or remove a data security policy |

Helpers are tagged `@ignore`, so they run only when a test calls them.

## Running SQL

Use the suite's shared SQL compute instead of starting your own. It is created once per run and reused:

```gherkin
@lock=sql
Feature: Orders, the daily totals add up

  Background:
    * url baseUrl
    * def sqlCompute = karate.callSingle('classpath:iomete/tests/sql/setup/sql-compute.feature', { domain: domain })
    * def table = 'spark_catalog.default.karate_orders_' + runId
    * def runQuery = function(sql) { return karate.call('classpath:iomete/helpers/query/run-query-v2.feature', { domain: domain, computeName: sqlCompute.computeName, statement: sql }).result }
    * configure afterScenario = function() { runQuery('DROP TABLE IF EXISTS ' + table) }

  Scenario: a sum over inserted rows is correct
    * runQuery('CREATE OR REPLACE TABLE ' + table + ' (id INT, amount INT)')
    * runQuery('INSERT INTO ' + table + ' VALUES (1, 10), (2, 32)')
    * def result = runQuery('SELECT SUM(amount) FROM ' + table)
    * match result.values == [ 42 ]
```

`result` holds `columns`, `values` and `dataCount`.

## Starting your own compute

Only start a compute when the test needs one to itself, for example to stop or reconfigure it. Use the `spark` lock, delete the compute in `afterScenario`, and keep it small:

```gherkin
@lock=spark
Feature: My compute, it starts and answers SQL

  Background:
    * url baseUrl
    * def computeName = 'karate-my-compute-' + runId
    * call read('classpath:iomete/helpers/compute/delete-compute.feature') { name: '#(computeName)' }
    * configure afterScenario = function() { karate.call('classpath:iomete/helpers/compute/delete-compute.feature', { name: computeName }) }

  Scenario: a new compute runs a query
    * def created = call read('classpath:iomete/helpers/compute/create-compute.feature') { name: '#(computeName)', singleNode: true, image: '#(sparkImage)' }
    * match created.computeId == '#string'
```

## Acting as another user

```gherkin
    * def password = 'Karate-' + runId + '!1'
    * def created = call read('classpath:iomete/helpers/user/create-user.feature') { username: '#(username)' }
    * call read('classpath:iomete/helpers/user/set-password.feature') { username: '#(username)', password: '#(password)' }
    # issuing a token needs at least one admin role, e.g. READ_ONLY_ADMIN
    * call read('classpath:iomete/helpers/user/add-roles.feature') { username: '#(username)', roles: ['READ_ONLY_ADMIN'] }
    * def login = call read('classpath:iomete/helpers/user/get-access-token.feature') { username: '#(username)', password: '#(password)' }
    * configure headers = { 'X-API-Token': '#(login.accessToken)', Authorization: '#("Bearer " + login.accessToken)' }
```

To check that a user *cannot* do something, give them only the roles the check needs. To check what they can query, use `query/run-query-v2-as.feature` with `userToken`. Switch back to the admin with `{ 'X-API-Token': '#(token)', Authorization: '#("Bearer " + token)' }`.

## Skipping

Skip a test when the install doesn't have what it needs. A skip is reported as such and doesn't fail the run.

```gherkin
    # an older install
    * if (!platformAtLeast('4.0.2')) karate.abort()

    # a test that changes platform-wide state
    * if (!platformChangesAllowed()) karate.abort()

    # a setting the user did not provide
    * def repoUrl = java.lang.System.getenv('MY_REPO_URL')
    * if (!repoUrl) karate.abort()
```

Log a reason before you skip so the report shows why: `karate.log('skipping: ...')`.

## Waiting for something to happen

Don't use fixed sleeps. Poll until the state you want, with a limit:

```gherkin
    * configure retry = { count: 60, interval: 5000 }
    Given path 'api/v2/domains', domain, 'compute', computeId
    And retry until response.status == 'ACTIVE'
    When method get
    Then status 200
```

## Running your test

```bash
make test-one FEATURE=custom-tests/my-test.feature      # one file
make test-one FEATURE=custom-tests/my-test.feature:12   # one scenario, by line
make test-one FEATURE=custom-tests                      # all your tests
make cleanup                                            # remove what the run created
```

Run `make clean` after you add, move or rename a feature file. With Docker, mount the folder: `-v "$PWD/custom-tests:/suite/custom-tests"`.

The report is `target/karate-reports/karate-summary.html` and shows every request and response. Passwords and tokens are hidden.

## Checklist

- [ ] The file is in `custom-tests/` and has a `@lock` tag on its first line.
- [ ] Every name it creates includes `runId`.
- [ ] Cleanup is registered in `afterScenario` before anything is created.
- [ ] It checks real results, not only status codes.
- [ ] It skips, rather than fails, when the install lacks what it needs.
- [ ] No hostnames, credentials or environment-specific values.
- [ ] It passes twice in a row, and `make cleanup` leaves nothing of it behind.
